import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import getConfiguration from '@salesforce/apex/CMS_StatusManagerController.getConfiguration';
import saveStatuses from '@salesforce/apex/CMS_StatusManagerController.saveStatuses';
import STATUS_REQUIRED from '@salesforce/label/c.CMS_Error_Status_Required';
import STATUS_TOO_LONG from '@salesforce/label/c.CMS_Error_Status_Too_Long';
import DUPLICATE_STATUS from '@salesforce/label/c.CMS_Error_Duplicate_Status';
import EXACTLY_ONE_DEFAULT from '@salesforce/label/c.CMS_Error_Exactly_One_Default';
import { isSameJob, reduceError, rowsForType, validateStatuses } from './statusRules';

export const DEPLOYMENT_CHANNEL = '/event/CMS_Status_Config_Deployed__e';
export const DEPLOY_TIMEOUT_MS = 120000;

const MESSAGES = {
	statusRequired: STATUS_REQUIRED,
	statusTooLong: STATUS_TOO_LONG,
	duplicateStatus: DUPLICATE_STATUS,
	exactlyOneDefault: EXACTLY_ONE_DEFAULT
};

/**
 * Campaign Member Statuses tab: lets users with the Campaign Member Status Manager permission set
 * maintain the protected statuses for each Campaign Type. Saving starts a metadata deployment;
 * the CMS_Status_Config_Deployed__e event reports when it has finished.
 */
export default class CmsStatusManager extends LightningElement {
	campaignTypes = [];
	statuses = [];
	selectedType;
	rows = [];
	validationErrors = [];
	loadError;
	isLoading = true;
	isDeploying = false;
	pendingJobId;
	subscription;
	deployTimeout;
	nextRowKey = 0;

	connectedCallback() {
		onError(() => {
			// Streaming problems are covered by the fallback timer in startDeployTimeout.
		});
		this.subscribeToDeployments();
		this.loadConfiguration();
	}

	disconnectedCallback() {
		if (this.subscription) {
			unsubscribe(this.subscription, () => {});
			this.subscription = undefined;
		}
		this.clearDeployTimeout();
	}

	async subscribeToDeployments() {
		try {
			this.subscription = await subscribe(DEPLOYMENT_CHANNEL, -1, (message) => this.handleDeploymentMessage(message));
		} catch {
			// Without streaming, the fallback timer in startDeployTimeout still ends the wait.
			this.subscription = undefined;
		}
	}

	async loadConfiguration() {
		this.isLoading = true;
		try {
			const config = await getConfiguration();
			this.campaignTypes = config?.campaignTypes || [];
			this.statuses = config?.statuses || [];
			this.loadError = undefined;
			this.resetRows();
		} catch (error) {
			this.loadError = reduceError(error);
		} finally {
			this.isLoading = false;
		}
	}

	get typeOptions() {
		return [...this.campaignTypes]
			.sort((first, second) => first.label.localeCompare(second.label))
			.map((type) => ({
				label: type.isConfigured ? `${type.label} (protected)` : type.label,
				value: type.value
			}));
	}

	get selectedTypeOption() {
		return this.campaignTypes.find((type) => type.value === this.selectedType);
	}

	get hasSelectedType() {
		return Boolean(this.selectedType);
	}

	get isTypeConfigured() {
		return Boolean(this.selectedTypeOption?.isConfigured);
	}

	get isTypeRetired() {
		const option = this.selectedTypeOption;
		return Boolean(option) && !option.isPicklistValue;
	}

	get hasRows() {
		return this.rows.length > 0;
	}

	get showStopProtectingNotice() {
		return this.hasSelectedType && !this.hasRows && this.isTypeConfigured;
	}

	get showNoStatusesHint() {
		return this.hasSelectedType && !this.hasRows && !this.isTypeConfigured;
	}

	get hasValidationErrors() {
		return this.validationErrors.length > 0;
	}

	get isSaveDisabled() {
		return this.isDeploying || !this.hasSelectedType || (!this.hasRows && !this.isTypeConfigured);
	}

	get isRemoveAllDisabled() {
		return this.isDeploying || !this.hasRows;
	}

	handleTypeChange(event) {
		this.selectedType = event.detail.value;
		this.resetRows();
	}

	resetRows() {
		this.validationErrors = [];
		this.rows = rowsForType(this.statuses, this.selectedType).map((record) => this.newRow(record));
	}

	newRow(source = {}) {
		return {
			key: `row-${this.nextRowKey++}`,
			developerName: source.developerName || null,
			status: source.status || '',
			isDefault: Boolean(source.isDefault),
			hasResponded: Boolean(source.hasResponded)
		};
	}

	updateRow(key, changes) {
		this.rows = this.rows.map((row) => (row.key === key ? { ...row, ...changes } : row));
	}

	handleStatusChange(event) {
		this.updateRow(event.target.dataset.key, { status: event.detail.value });
	}

	handleDefaultChange(event) {
		const key = event.target.dataset.key;
		const checked = event.detail.checked;
		// Only one default: ticking one clears the others.
		this.rows = this.rows.map((row) => {
			if (row.key === key) {
				return { ...row, isDefault: checked };
			}
			return checked ? { ...row, isDefault: false } : row;
		});
	}

	handleRespondedChange(event) {
		this.updateRow(event.target.dataset.key, { hasResponded: event.detail.checked });
	}

	handleAddRow() {
		this.rows = [...this.rows, this.newRow({ isDefault: this.rows.length === 0 })];
	}

	handleRemoveRow(event) {
		const key = event.currentTarget.dataset.key;
		this.rows = this.rows.filter((row) => row.key !== key);
	}

	handleRemoveAll() {
		this.rows = [];
	}

	handleCancel() {
		this.resetRows();
	}

	handleRefresh() {
		this.loadConfiguration();
	}

	async handleSave() {
		this.validationErrors = validateStatuses(this.rows, MESSAGES);
		if (this.hasValidationErrors) {
			return;
		}
		this.isDeploying = true;
		try {
			const jobId = await saveStatuses({
				campaignType: this.selectedType,
				statuses: this.rows.map(({ developerName, status, isDefault, hasResponded }) => ({
					developerName,
					status: status.trim(),
					isDefault,
					hasResponded
				}))
			});
			this.pendingJobId = jobId;
			this.startDeployTimeout();
		} catch (error) {
			this.isDeploying = false;
			this.showToast('error', 'Changes not saved', reduceError(error));
		}
	}

	handleDeploymentMessage(message) {
		const payload = message?.data?.payload;
		if (!payload || !isSameJob(payload.Job_Id__c, this.pendingJobId)) {
			return;
		}
		this.finishDeployment();
		if (payload.Success__c) {
			this.showToast('success', 'Changes saved', `The statuses for ${this.selectedType} are updated.`);
			this.loadConfiguration();
		} else {
			this.showToast('error', 'Changes not saved', payload.Message__c || 'The deployment failed. Check Setup > Deployment Status.');
		}
	}

	startDeployTimeout() {
		this.clearDeployTimeout();
		// eslint-disable-next-line @lwc/lwc/no-async-operation
		this.deployTimeout = setTimeout(() => {
			this.finishDeployment();
			this.showToast('info', 'Still saving', 'This is taking longer than usual. Refresh in a minute, or check Setup > Deployment Status.');
		}, DEPLOY_TIMEOUT_MS);
	}

	finishDeployment() {
		this.clearDeployTimeout();
		this.isDeploying = false;
		this.pendingJobId = undefined;
	}

	clearDeployTimeout() {
		if (this.deployTimeout) {
			clearTimeout(this.deployTimeout);
			this.deployTimeout = undefined;
		}
	}

	showToast(variant, title, message) {
		this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
	}
}
