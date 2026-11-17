/**
 * Pure helpers for the Campaign Member Statuses tab. Kept free of LWC imports so they can be
 * unit tested directly. The server (CMS_StatusManagerController) applies the same rules; these
 * only give the user faster feedback.
 */

export const MAX_STATUS_LENGTH = 255;

/**
 * Normalise a Campaign Type or status name for case-insensitive comparison.
 * @param {string} value
 * @returns {string}
 */
export function toKey(value) {
	return (value || '').trim().toLowerCase();
}

/**
 * Replace {0}, {1}... in a custom label with values.
 * @param {string} template
 * @param {...string} values
 * @returns {string}
 */
export function formatLabel(template, ...values) {
	return (template || '').replace(/\{(\d+)\}/g, (match, index) => (values[index] === undefined ? match : values[index]));
}

/**
 * Validate the statuses for one Campaign Type before saving.
 * An empty list is valid: it stops protecting the Campaign Type.
 * @param {Array<{status: string, isDefault: boolean}>} rows
 * @param {{statusRequired: string, statusTooLong: string, duplicateStatus: string, exactlyOneDefault: string}} messages
 * @returns {string[]} error messages, empty when valid
 */
export function validateStatuses(rows, messages) {
	const errors = [];
	const addError = (message) => {
		if (!errors.includes(message)) {
			errors.push(message);
		}
	};
	if (!rows || rows.length === 0) {
		return errors;
	}

	const seen = new Set();
	let defaultCount = 0;
	rows.forEach((row) => {
		const name = (row.status || '').trim();
		if (row.isDefault) {
			defaultCount++;
		}
		if (!name) {
			addError(messages.statusRequired);
			return;
		}
		if (name.length > MAX_STATUS_LENGTH) {
			addError(formatLabel(messages.statusTooLong, `${name.substring(0, 50)}...`));
		}
		const key = toKey(name);
		if (seen.has(key)) {
			addError(formatLabel(messages.duplicateStatus, name));
		}
		seen.add(key);
	});

	if (defaultCount !== 1) {
		addError(messages.exactlyOneDefault);
	}
	return errors;
}

/**
 * Active statuses for one Campaign Type, default first, then responded, then by name.
 * @param {Array} statuses records from getConfiguration
 * @param {string} campaignType
 * @returns {Array}
 */
export function rowsForType(statuses, campaignType) {
	if (!campaignType) {
		return [];
	}
	const typeKey = toKey(campaignType);
	return (statuses || [])
		.filter((record) => !record.inactive && toKey(record.campaignType) === typeKey)
		.sort((first, second) => {
			if (first.isDefault !== second.isDefault) {
				return first.isDefault ? -1 : 1;
			}
			if (first.hasResponded !== second.hasResponded) {
				return first.hasResponded ? -1 : 1;
			}
			return toKey(first.status).localeCompare(toKey(second.status));
		});
}

/**
 * Compare deployment job Ids, allowing for 15 and 18 character forms.
 * @param {string} first
 * @param {string} second
 * @returns {boolean}
 */
export function isSameJob(first, second) {
	if (!first || !second) {
		return false;
	}
	return first.substring(0, 15) === second.substring(0, 15);
}

/**
 * Turn an Apex or JavaScript error into a readable message.
 * @param {*} error
 * @returns {string}
 */
export function reduceError(error) {
	if (!error) {
		return 'Unknown error';
	}
	if (Array.isArray(error.body)) {
		return error.body.map((item) => item.message).join(', ');
	}
	if (error.body && typeof error.body.message === 'string') {
		return error.body.message;
	}
	if (typeof error.message === 'string') {
		return error.message;
	}
	return 'Unknown error';
}
