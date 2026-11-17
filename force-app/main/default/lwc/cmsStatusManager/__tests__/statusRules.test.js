import { formatLabel, isSameJob, reduceError, rowsForType, toKey, validateStatuses, MAX_STATUS_LENGTH } from '../statusRules';

const MESSAGES = {
	statusRequired: 'required',
	statusTooLong: 'too long: {0}',
	duplicateStatus: 'duplicate: {0}',
	exactlyOneDefault: 'one default'
};

describe('statusRules.validateStatuses', () => {
	it('accepts a valid list with one default', () => {
		const rows = [
			{ status: 'Registered', isDefault: true },
			{ status: 'Attended', isDefault: false }
		];
		expect(validateStatuses(rows, MESSAGES)).toEqual([]);
	});

	it('accepts an empty list because it stops protecting the type', () => {
		expect(validateStatuses([], MESSAGES)).toEqual([]);
	});

	it('requires a name for every status', () => {
		expect(validateStatuses([{ status: '   ', isDefault: true }], MESSAGES)).toEqual(['required']);
	});

	it('rejects names longer than the limit', () => {
		const errors = validateStatuses([{ status: 'x'.repeat(MAX_STATUS_LENGTH + 1), isDefault: true }], MESSAGES);
		expect(errors).toHaveLength(1);
		expect(errors[0]).toMatch(/^too long: x{50}\.\.\.$/);
	});

	it('rejects duplicate names ignoring case and spaces', () => {
		const rows = [
			{ status: 'Attended', isDefault: true },
			{ status: ' attended ', isDefault: false }
		];
		expect(validateStatuses(rows, MESSAGES)).toEqual(['duplicate: attended']);
	});

	it('rejects two defaults', () => {
		const rows = [
			{ status: 'Registered', isDefault: true },
			{ status: 'Attended', isDefault: true }
		];
		expect(validateStatuses(rows, MESSAGES)).toEqual(['one default']);
	});

	it('rejects no default', () => {
		expect(validateStatuses([{ status: 'Registered', isDefault: false }], MESSAGES)).toEqual(['one default']);
	});

	it('reports each message once', () => {
		const rows = [
			{ status: '', isDefault: false },
			{ status: '', isDefault: false }
		];
		expect(validateStatuses(rows, MESSAGES)).toEqual(['required', 'one default']);
	});
});

describe('statusRules.rowsForType', () => {
	const statuses = [
		{ campaignType: 'Webinar', status: 'Did Not Attend', isDefault: false, hasResponded: false, inactive: false },
		{ campaignType: 'webinar', status: 'Attended', isDefault: false, hasResponded: true, inactive: false },
		{ campaignType: 'Webinar', status: 'Registered', isDefault: true, hasResponded: false, inactive: false },
		{ campaignType: 'Webinar', status: 'Old', isDefault: false, hasResponded: false, inactive: true },
		{ campaignType: 'Email', status: 'Sent', isDefault: true, hasResponded: false, inactive: false }
	];

	it('returns active statuses for the type, default first then responded then by name', () => {
		expect(rowsForType(statuses, 'WEBINAR').map((row) => row.status)).toEqual(['Registered', 'Attended', 'Did Not Attend']);
	});

	it('returns nothing when no type is selected', () => {
		expect(rowsForType(statuses, undefined)).toEqual([]);
	});

	it('handles missing statuses', () => {
		expect(rowsForType(undefined, 'Webinar')).toEqual([]);
	});
});

describe('statusRules helpers', () => {
	it('normalises keys', () => {
		expect(toKey('  Webinar ')).toBe('webinar');
		expect(toKey(undefined)).toBe('');
	});

	it('formats labels and leaves unknown placeholders alone', () => {
		expect(formatLabel('{0} and {1}', 'a')).toBe('a and {1}');
	});

	it('matches 15 and 18 character job Ids', () => {
		expect(isSameJob('0Af000000000001AAA', '0Af000000000001')).toBe(true);
		expect(isSameJob('0Af000000000002', '0Af000000000001')).toBe(false);
		expect(isSameJob(undefined, '0Af000000000001')).toBe(false);
	});

	it('reduces Apex and JavaScript errors to a message', () => {
		expect(reduceError({ body: { message: 'from apex' } })).toBe('from apex');
		expect(reduceError({ body: [{ message: 'a' }, { message: 'b' }] })).toBe('a, b');
		expect(reduceError(new Error('from js'))).toBe('from js');
		expect(reduceError(undefined)).toBe('Unknown error');
		expect(reduceError({})).toBe('Unknown error');
	});
});
