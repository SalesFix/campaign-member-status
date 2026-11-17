import { createElement } from 'lwc';
import CmsStatusManager, { DEPLOYMENT_CHANNEL, DEPLOY_TIMEOUT_MS } from 'c/cmsStatusManager';
import { subscribe } from 'lightning/empApi';
import getConfiguration from '@salesforce/apex/CMS_StatusManagerController.getConfiguration';
import saveStatuses from '@salesforce/apex/CMS_StatusManagerController.saveStatuses';

jest.mock('@salesforce/apex/CMS_StatusManagerController.getConfiguration', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/CMS_StatusManagerController.saveStatuses', () => ({ default: jest.fn() }), { virtual: true });

const JOB_ID = '0Af000000000001AAA';

const CONFIGURATION = {
	campaignTypes: [
		{ value: 'Webinar', label: 'Webinar', isConfigured: true, isPicklistValue: true },
		{ value: 'Email', label: 'Email', isConfigured: false, isPicklistValue: true },
		{ value: 'Old Type', label: 'Old Type', isConfigured: true, isPicklistValue: false }
	],
	statuses: [
		{ developerName: 'Webinar_Registered', campaignType: 'Webinar', status: 'Registered', isDefault: true, hasResponded: false, inactive: false },
		{ developerName: 'Webinar_Attended', campaignType: 'Webinar', status: 'Attended', isDefault: false, hasResponded: true, inactive: false },
		{ developerName: 'Webinar_Old', campaignType: 'Webinar', status: 'Old', isDefault: false, hasResponded: false, inactive: true },
		{ developerName: 'Old_Type_Sent', campaignType: 'Old Type', status: 'Sent', isDefault: true, hasResponded: false, inactive: false }
	]
};

const flushPromises = () =>
	new Promise((resolve) => {
		process.nextTick(resolve);
	});

async function renderComponent() {
	const element = createElement('c-cms-status-manager', { is: CmsStatusManager });
	document.body.appendChild(element);
	await flushPromises();
	return element;
}

async function selectType(element, value) {
	const picker = element.shadowRoot.querySelector('[data-id="type-picker"]');
	picker.dispatchEvent(new CustomEvent('change', { detail: { value } }));
	await flushPromises();
}

function rows(element) {
	return element.shadowRoot.querySelectorAll('[data-id="status-row"]');
}

function click(element, dataId) {
	element.shadowRoot.querySelector(`[data-id="${dataId}"]`).dispatchEvent(new CustomEvent('click'));
	return flushPromises();
}

function deploymentCallback() {
	const call = subscribe.mock.calls.find((args) => args[0] === DEPLOYMENT_CHANNEL);
	return call[2];
}

describe('c-cms-status-manager', () => {
	beforeEach(() => {
		getConfiguration.mockResolvedValue(CONFIGURATION);
		saveStatuses.mockResolvedValue(JOB_ID);
	});

	afterEach(() => {
		while (document.body.firstChild) {
			document.body.removeChild(document.body.firstChild);
		}
		jest.clearAllMocks();
		jest.useRealTimers();
	});

	it('lists Campaign Types alphabetically and marks protected ones', async () => {
		const element = await renderComponent();

		const options = element.shadowRoot.querySelector('[data-id="type-picker"]').options;
		expect(options.map((option) => option.label)).toEqual(['Email', 'Old Type (protected)', 'Webinar (protected)']);
	});

	it('subscribes to deployment events', async () => {
		await renderComponent();

		expect(subscribe).toHaveBeenCalledWith(DEPLOYMENT_CHANNEL, -1, expect.any(Function));
	});

	it('shows the server message when loading fails', async () => {
		getConfiguration.mockRejectedValue({ body: { message: 'No permission' } });

		const element = await renderComponent();

		expect(element.shadowRoot.querySelector('[data-id="load-error"]').textContent).toBe('No permission');
	});

	it('shows only active statuses for the selected type', async () => {
		const element = await renderComponent();

		await selectType(element, 'Webinar');

		const names = Array.from(element.shadowRoot.querySelectorAll('[data-id="status-name"]')).map((input) => input.value);
		expect(names).toEqual(['Registered', 'Attended']);
	});

	it('warns when the type is no longer a picklist value', async () => {
		const element = await renderComponent();

		await selectType(element, 'Old Type');

		expect(element.shadowRoot.querySelector('[data-id="retired-type"]')).not.toBeNull();
	});

	it('prompts to add statuses for an unprotected type and disables Save', async () => {
		const element = await renderComponent();

		await selectType(element, 'Email');

		expect(element.shadowRoot.querySelector('[data-id="no-statuses"]')).not.toBeNull();
		expect(element.shadowRoot.querySelector('[data-id="save"]').disabled).toBe(true);
	});

	it('adds a row and makes the first row the default', async () => {
		const element = await renderComponent();
		await selectType(element, 'Email');

		await click(element, 'add-row');

		expect(rows(element)).toHaveLength(1);
		expect(element.shadowRoot.querySelector('[data-id="status-default"]').checked).toBe(true);
	});

	it('keeps only one default when another is ticked', async () => {
		const element = await renderComponent();
		await selectType(element, 'Webinar');

		const defaults = element.shadowRoot.querySelectorAll('[data-id="status-default"]');
		defaults[1].dispatchEvent(new CustomEvent('change', { detail: { checked: true } }));
		await flushPromises();

		const checked = Array.from(element.shadowRoot.querySelectorAll('[data-id="status-default"]')).map((input) => input.checked);
		expect(checked).toEqual([false, true]);
	});

	it('shows validation errors and does not save when a name is blank', async () => {
		const element = await renderComponent();
		await selectType(element, 'Webinar');
		await click(element, 'add-row');

		await click(element, 'save');

		expect(element.shadowRoot.querySelector('[data-id="validation-errors"]').textContent).toContain('c.CMS_Error_Status_Required');
		expect(saveStatuses).not.toHaveBeenCalled();
	});

	it('warns before stopping protection when all statuses are removed', async () => {
		const element = await renderComponent();
		await selectType(element, 'Webinar');

		await click(element, 'remove-all');

		expect(rows(element)).toHaveLength(0);
		expect(element.shadowRoot.querySelector('[data-id="stop-protecting"]')).not.toBeNull();
		expect(element.shadowRoot.querySelector('[data-id="save"]').disabled).toBe(false);
	});

	it('removes one row', async () => {
		const element = await renderComponent();
		await selectType(element, 'Webinar');

		await click(element, 'remove-row');

		expect(rows(element)).toHaveLength(1);
	});

	it('restores the saved statuses on Cancel', async () => {
		const element = await renderComponent();
		await selectType(element, 'Webinar');
		await click(element, 'remove-all');

		await click(element, 'cancel');

		expect(rows(element)).toHaveLength(2);
	});

	it('sends trimmed statuses and reports success when the deployment finishes', async () => {
		const element = await renderComponent();
		await selectType(element, 'Webinar');
		const nameInput = element.shadowRoot.querySelector('[data-id="status-name"]');
		nameInput.dispatchEvent(new CustomEvent('change', { detail: { value: '  Registered Now  ' } }));
		await flushPromises();
		const toastHandler = jest.fn();
		element.addEventListener('lightning__showtoast', toastHandler);

		await click(element, 'save');

		expect(saveStatuses).toHaveBeenCalledWith({
			campaignType: 'Webinar',
			statuses: [
				{ developerName: 'Webinar_Registered', status: 'Registered Now', isDefault: true, hasResponded: false },
				{ developerName: 'Webinar_Attended', status: 'Attended', isDefault: false, hasResponded: true }
			]
		});
		expect(element.shadowRoot.querySelector('[data-id="deploying"]')).not.toBeNull();

		deploymentCallback()({ data: { payload: { Job_Id__c: JOB_ID, Success__c: true } } });
		await flushPromises();

		expect(toastHandler.mock.calls[0][0].detail.variant).toBe('success');
		expect(getConfiguration).toHaveBeenCalledTimes(2);
		expect(element.shadowRoot.querySelector('[data-id="deploying"]')).toBeNull();
	});

	it('ignores deployment events for other jobs', async () => {
		const element = await renderComponent();
		await selectType(element, 'Webinar');
		await click(element, 'save');

		deploymentCallback()({ data: { payload: { Job_Id__c: '0Af000000000999AAA', Success__c: true } } });
		await flushPromises();

		expect(element.shadowRoot.querySelector('[data-id="deploying"]')).not.toBeNull();
	});

	it('reports the failure message when the deployment fails', async () => {
		const element = await renderComponent();
		await selectType(element, 'Webinar');
		const toastHandler = jest.fn();
		element.addEventListener('lightning__showtoast', toastHandler);
		await click(element, 'save');

		deploymentCallback()({ data: { payload: { Job_Id__c: JOB_ID, Success__c: false, Message__c: 'Invalid value' } } });
		await flushPromises();

		expect(toastHandler.mock.calls[0][0].detail.variant).toBe('error');
		expect(toastHandler.mock.calls[0][0].detail.message).toBe('Invalid value');
	});

	it('reports a server-side validation error without starting a deployment', async () => {
		saveStatuses.mockRejectedValue({ body: { message: 'Choose exactly one default status.' } });
		const element = await renderComponent();
		await selectType(element, 'Webinar');
		const toastHandler = jest.fn();
		element.addEventListener('lightning__showtoast', toastHandler);

		await click(element, 'save');

		expect(toastHandler.mock.calls[0][0].detail.message).toBe('Choose exactly one default status.');
		expect(element.shadowRoot.querySelector('[data-id="deploying"]')).toBeNull();
	});

	it('stops waiting and tells the user when the deployment takes too long', async () => {
		jest.useFakeTimers({ doNotFake: ['nextTick', 'setImmediate'] });
		const element = await renderComponent();
		await selectType(element, 'Webinar');
		const toastHandler = jest.fn();
		element.addEventListener('lightning__showtoast', toastHandler);
		await click(element, 'save');

		jest.advanceTimersByTime(DEPLOY_TIMEOUT_MS);
		await flushPromises();

		expect(toastHandler.mock.calls[0][0].detail.variant).toBe('info');
		expect(element.shadowRoot.querySelector('[data-id="deploying"]')).toBeNull();
	});

	it('reloads when Refresh is clicked', async () => {
		const element = await renderComponent();

		await click(element, 'refresh');

		expect(getConfiguration).toHaveBeenCalledTimes(2);
	});
});
