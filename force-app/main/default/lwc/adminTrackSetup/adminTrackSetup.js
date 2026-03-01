import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getJobStatus      from '@salesforce/apex/AdminTrackSchedulerService.getJobStatus';
import scheduleJob       from '@salesforce/apex/AdminTrackSchedulerService.scheduleJob';
import deactivateJob     from '@salesforce/apex/AdminTrackSchedulerService.deactivateJob';
import runNow            from '@salesforce/apex/AdminTrackSchedulerService.runNow';
import getSlackSettings  from '@salesforce/apex/AdminTrackSchedulerService.getSlackSettings';
import saveSlackSettings from '@salesforce/apex/AdminTrackSchedulerService.saveSlackSettings';
import getExclusions   from '@salesforce/apex/AdminTrackExclusionService.getExclusions';
import addExclusion    from '@salesforce/apex/AdminTrackExclusionService.addExclusion';
import toggleExclusion from '@salesforce/apex/AdminTrackExclusionService.toggleExclusion';
import deleteExclusion from '@salesforce/apex/AdminTrackExclusionService.deleteExclusion';
import getLogs     from '@salesforce/apex/AdminTrackLogService.getLogs';
import getSections from '@salesforce/apex/AdminTrackLogService.getSections';

const INTERVAL_OPTIONS = [
    { label: '5 minutes',  value: '5'  },
    { label: '15 minutes', value: '15' },
    { label: '30 minutes', value: '30' },
    { label: '60 minutes', value: '60' }
];

const SCHEDULED_JOB_COLUMNS = [
    { label: 'Job Name',   fieldName: 'name',         type: 'text'                    },
    { label: 'State',      fieldName: 'state',        type: 'text', initialWidth: 110 },
    { label: 'Next Run',   fieldName: 'nextFireTime', type: 'text'                    },
    { label: 'Last Run',   fieldName: 'prevFireTime', type: 'text'                    },
    { label: 'Created By', fieldName: 'createdBy',    type: 'text', initialWidth: 160 }
];

const PROCESSOR_RUN_COLUMNS = [
    { label: 'Run Date',   fieldName: 'runDate',   type: 'text'                      },
    { label: 'Window',     fieldName: 'window',    type: 'text'                      },
    { label: 'Changes',    fieldName: 'changes',   type: 'number', initialWidth: 100 },
    { label: 'Excluded',   fieldName: 'excluded',  type: 'number', initialWidth: 100 },
    { label: 'Slack Sent', fieldName: 'slackSent', type: 'boolean', initialWidth: 110 }
];

const DATE_RANGE_OPTIONS = [
    { label: 'Today',        value: 'today'      },
    { label: 'Yesterday',    value: 'yesterday'  },
    { label: 'Last 7 Days',  value: '7'          },
    { label: 'Last 30 Days', value: '30'         },
    { label: 'This Month',   value: 'this_month' },
    { label: 'Last Month',   value: 'last_month' },
    { label: 'Last 90 Days', value: '90'         },
    { label: 'Last 180 Days',value: '180'        },
    { label: 'Custom',       value: 'custom'     }
];

const EXCLUSION_TYPE_OPTIONS = [
    { label: 'Section', value: 'Section' },
    { label: 'Action',  value: 'Action'  },
    { label: 'User',    value: 'User'    }
];

const EXCLUSION_COLUMNS = [
    { label: 'Type',   fieldName: 'ExclusionType__c',  type: 'text',    initialWidth: 120 },
    { label: 'Value',  fieldName: 'ExclusionValue__c', type: 'text'                       },
    { label: 'Active', fieldName: 'IsActive__c',       type: 'boolean', initialWidth: 100 },
    {
        type: 'action',
        typeAttributes: {
            rowActions: [
                { label: 'Toggle Active', name: 'toggle' },
                { label: 'Delete',        name: 'delete' }
            ]
        }
    }
];

const LOG_COLUMNS = [
    { label: 'Date',    fieldName: 'CreatedDate',    type: 'date',
      typeAttributes: { year: 'numeric', month: '2-digit', day: '2-digit',
                        hour: '2-digit', minute: '2-digit' }, initialWidth: 160 },
    { label: 'Section', fieldName: 'Section',        type: 'text', initialWidth: 160 },
    { label: 'Action',  fieldName: 'Action',         type: 'text', initialWidth: 160 },
    { label: 'User',    fieldName: 'createdByName',  type: 'text', initialWidth: 160 },
    { label: 'Details', fieldName: 'Display',        type: 'text'                    }
];

export default class AdminTrackSetup extends LightningElement {

    // ─── Scheduler ──────────────────────────────────────────────────────────────
    @track jobStatus       = { isActive: false, nextRunTime: null, intervalMinutes: null };
    @track intervalMinutes = '15';
    @track isLoading       = false;
    @track error           = false;
    @track errorMessage    = '';
    @track successMessage  = '';

    @track scheduledJobs  = [];
    @track processorRuns  = [];

    // ─── Exclusions ──────────────────────────────────────────────────────────────
    @track exclusions        = [];
    @track newExclusionType  = 'Section';
    @track newExclusionValue = '';

    // ─── Slack Configuration ─────────────────────────────────────────────────────
    @track slackEnabled         = false;
    @track slackWebhookUrl      = '';
    @track slackMessageTemplate = '';
    @track slackMaxDetails      = 25;
    @track isSavingSlack        = false;

    // ─── Audit Log ───────────────────────────────────────────────────────────────
    @track logs            = [];
    @track logSearchTerm   = '';
    @track isLoadingLogs   = false;
    @track logsLoaded      = false;
    @track logDateRange    = '7';
    @track customStartDate = '';
    @track customEndDate   = '';
    @track sectionFilter   = '';
    @track userFilter      = '';
    @track sectionOptions  = [];

    // ─── Wire: job status on init ────────────────────────────────────────────────

    @wire(getJobStatus)
    wiredJobStatus({ data, error }) {
        if (data) {
            this.applyJobStatus(data);
            this.error = false;
        } else if (error) {
            this.setError('Failed to load scheduler status: ' + this.extractMessage(error));
        }
    }

    connectedCallback() {
        this.loadExclusions();
        this.loadSlackSettings();
    }

    // ─── Computed: scheduler ─────────────────────────────────────────────────────

    get intervalOptions()       { return INTERVAL_OPTIONS; }
    get scheduledJobColumns()   { return SCHEDULED_JOB_COLUMNS; }
    get processorRunColumns()   { return PROCESSOR_RUN_COLUMNS; }
    get hasScheduledJobs()      { return this.scheduledJobs.length > 0; }
    get hasProcessorRuns()      { return this.processorRuns.length > 0; }

    get processorRunTotalLabel() {
        const total = this.processorRuns.reduce((sum, r) => sum + (r.changes || 0), 0);
        const n     = this.processorRuns.length;
        return `${total} total change${total !== 1 ? 's' : ''} across last ${n} run${n !== 1 ? 's' : ''}`;
    }

    get nextRunDisplay() {
        return this.jobStatus.nextRunTime || '—';
    }

    get currentIntervalLabel() {
        const minutes = this.jobStatus.intervalMinutes;
        if (!minutes) return '—';
        const match = INTERVAL_OPTIONS.find(o => o.value === String(minutes));
        return match ? match.label : minutes + ' minutes';
    }

    // ─── Computed: exclusions ────────────────────────────────────────────────────

    get exclusionTypeOptions() { return EXCLUSION_TYPE_OPTIONS; }
    get exclusionColumns()     { return EXCLUSION_COLUMNS; }
    get hasExclusions()        { return this.exclusions.length > 0; }

    get tokenHelpText() {
        return 'Tokens: {count} · {orgName} · {timestamp}. Leave blank to use the default format, which lists every change across multiple messages if needed.';
    }

    get isAddDisabled() {
        return !this.newExclusionValue || !this.newExclusionValue.trim() || this.isLoading;
    }

    get newValuePlaceholder() {
        switch (this.newExclusionType) {
            case 'Section': return 'e.g. Manage Users';
            case 'Action':  return 'e.g. PasswordReset';
            case 'User':    return 'Salesforce User ID (15 or 18 chars)';
            default:        return '';
        }
    }

    // ─── Computed: audit log ─────────────────────────────────────────────────────

    get logColumns()        { return LOG_COLUMNS; }
    get dateRangeOptions()  { return DATE_RANGE_OPTIONS; }
    get isCustomDateRange() { return this.logDateRange === 'custom'; }

    get sectionPicklistOptions() {
        return [
            { label: 'All Sections', value: '' },
            ...this.sectionOptions.map(s => ({ label: s, value: s }))
        ];
    }
    get isApplyDisabled() {
        return (this.logDateRange === 'custom' && !this.customStartDate) || this.isLoadingLogs;
    }

    get filteredLogs() {
        let results = this.logs;

        // Section: client-side exact match (SetupAuditTrail.Section is not SOQL-filterable)
        if (this.sectionFilter) {
            results = results.filter(log => log.Section === this.sectionFilter);
        }

        // Text search
        const term = (this.logSearchTerm || '').trim().toLowerCase();
        if (!term) return results;
        return results.filter(log =>
            (log.Action       && log.Action.toLowerCase().includes(term))       ||
            (log.Section      && log.Section.toLowerCase().includes(term))      ||
            (log.Display      && log.Display.toLowerCase().includes(term))      ||
            (log.createdByName && log.createdByName.toLowerCase().includes(term))
        );
    }

    get hasFilteredLogs() { return this.filteredLogs.length > 0; }

    get logCountLabel() {
        const total    = this.logs.length;
        const filtered = this.filteredLogs.length;
        const suffix   = total === 500 ? ' (showing up to 500)' : '';
        if (!this.logSearchTerm || !this.logSearchTerm.trim()) {
            return `${total} record${total !== 1 ? 's' : ''}${suffix}`;
        }
        return `${filtered} of ${total} record${total !== 1 ? 's' : ''} match${suffix}`;
    }

    // ─── Scheduler handlers ──────────────────────────────────────────────────────

    handleIntervalChange(event) {
        this.intervalMinutes = event.detail.value;
    }

    async handleActivate() {
        this.clearMessages();
        this.isLoading = true;
        try {
            await scheduleJob({ intervalMinutes: parseInt(this.intervalMinutes, 10) });
            const label = INTERVAL_OPTIONS.find(o => o.value === this.intervalMinutes)?.label || this.intervalMinutes + ' min';
            this.successMessage = `Scheduler activated — polling every ${label}.`;
            await this.refreshStatus();
        } catch (err) {
            this.setError('Activate failed: ' + this.extractMessage(err));
        } finally {
            this.isLoading = false;
        }
    }

    async handleDeactivate() {
        this.clearMessages();
        this.isLoading = true;
        try {
            await deactivateJob();
            this.successMessage = 'Scheduler deactivated successfully.';
            await this.refreshStatus();
        } catch (err) {
            this.setError('Deactivate failed: ' + this.extractMessage(err));
        } finally {
            this.isLoading = false;
        }
    }

    async handleRunNow() {
        this.clearMessages();
        this.isLoading = true;
        try {
            await runNow();
            this.dispatchEvent(new ShowToastEvent({
                title:   'Batch Started',
                message: 'AdminTrack batch job submitted. Check Apex Jobs for progress.',
                variant: 'success'
            }));
            this.successMessage = 'Batch job submitted. Results will appear in Audit Log records shortly.';
        } catch (err) {
            this.setError('Run Now failed: ' + this.extractMessage(err));
        } finally {
            this.isLoading = false;
        }
    }

    async handleRefresh() {
        this.clearMessages();
        await this.refreshStatus();
    }

    // ─── Exclusion handlers ──────────────────────────────────────────────────────

    handleNewTypeChange(event) {
        this.newExclusionType  = event.detail.value;
        this.newExclusionValue = '';
    }

    handleNewValueChange(event) {
        this.newExclusionValue = event.target.value;
    }

    async handleAddExclusion() {
        if (!this.newExclusionValue || !this.newExclusionValue.trim()) return;
        this.clearMessages();
        this.isLoading = true;
        try {
            await addExclusion({
                exclusionType:  this.newExclusionType,
                exclusionValue: this.newExclusionValue.trim()
            });
            this.newExclusionValue = '';
            this.successMessage = 'Exclusion rule added.';
            await this.loadExclusions();
        } catch (err) {
            this.setError('Add failed: ' + this.extractMessage(err));
        } finally {
            this.isLoading = false;
        }
    }

    async handleExclusionRowAction(event) {
        const action = event.detail.action.name;
        const row    = event.detail.row;
        this.clearMessages();
        this.isLoading = true;
        try {
            if (action === 'delete') {
                await deleteExclusion({ exclusionId: row.Id });
                this.successMessage = 'Exclusion rule deleted.';
            } else if (action === 'toggle') {
                await toggleExclusion({ exclusionId: row.Id, isActive: !row.IsActive__c });
                this.successMessage = 'Exclusion rule updated.';
            }
            await this.loadExclusions();
        } catch (err) {
            this.setError('Action failed: ' + this.extractMessage(err));
        } finally {
            this.isLoading = false;
        }
    }

    // ─── Slack Configuration handlers ────────────────────────────────────────────

    handleSlackEnabledChange(event) {
        this.slackEnabled = event.target.checked;
    }

    handleWebhookUrlChange(event) {
        this.slackWebhookUrl = event.target.value;
    }

    handleTemplateChange(event) {
        this.slackMessageTemplate = event.target.value;
    }

    handleSlackMaxDetailsChange(event) {
        this.slackMaxDetails = parseInt(event.target.value, 10) || 10;
    }

    async handleSaveSlackSettings() {
        this.clearMessages();
        this.isSavingSlack = true;
        try {
            await saveSlackSettings({
                slackEnabled:         this.slackEnabled,
                slackWebhookUrl:      this.slackWebhookUrl,
                slackMessageTemplate: this.slackMessageTemplate,
                slackMaxDetails:      this.slackMaxDetails
            });
            this.successMessage = this.slackEnabled
                ? 'Slack settings saved. A confirmation message was sent to your channel.'
                : 'Slack settings saved.';
        } catch (err) {
            this.setError('Failed to save Slack settings: ' + this.extractMessage(err));
        } finally {
            this.isSavingSlack = false;
        }
    }

    // ─── Audit Log handlers ──────────────────────────────────────────────────────

    handleLogTabActive() {
        if (this.sectionOptions.length === 0) {
            this.loadSections();
        }
        if (!this.logsLoaded) {
            this.loadLogs();
        }
    }

    handleLogSearch(event) {
        this.logSearchTerm = event.target.value;
    }

    async handleReloadLogs() {
        this.logsLoaded = false;
        await this.loadLogs();
    }

    handleDateRangeChange(event) {
        this.logDateRange = event.detail.value;
        if (this.logDateRange !== 'custom') {
            this.logsLoaded = false;
            this.loadLogs();
        }
    }

    handleCustomStartDate(event) {
        this.customStartDate = event.target.value;
    }

    handleCustomEndDate(event) {
        this.customEndDate = event.target.value;
    }

    handleSectionFilterChange(event) {
        this.sectionFilter = event.detail.value;
    }

    handleUserSelect(event) {
        this.userFilter = event.detail.recordId || null;
        this.logsLoaded = false;
        this.loadLogs();
    }

    handleApplyFilters() {
        this.logsLoaded = false;
        this.loadLogs();
    }

    // ─── Private helpers ─────────────────────────────────────────────────────────

    async loadSlackSettings() {
        try {
            const data = await getSlackSettings();
            this.slackEnabled         = data.slackEnabled;
            this.slackWebhookUrl      = data.slackWebhookUrl      || '';
            this.slackMessageTemplate = data.slackMessageTemplate || '';
            this.slackMaxDetails      = data.slackMaxDetails      || 10;
        } catch (err) {
            this.setError('Failed to load Slack settings: ' + this.extractMessage(err));
        }
    }

    async loadExclusions() {
        try {
            this.exclusions = await getExclusions();
        } catch (err) {
            this.setError('Failed to load exclusions: ' + this.extractMessage(err));
        }
    }

    async loadLogs() {
        this.isLoadingLogs = true;
        try {
            const { sinceStr, untilStr } = this.computeDateRange();
            if (!sinceStr) {
                return; // Custom range selected but no start date yet
            }
            const raw = await getLogs({
                sinceStr,
                untilStr,
                sectionFilter: null,
                userId:        this.userFilter || null
            });
            this.logs = raw.map(r => ({
                ...r,
                createdByName: r.CreatedBy ? r.CreatedBy.Name : '—'
            }));
            this.logsLoaded = true;
        } catch (err) {
            this.setError('Failed to load audit log: ' + this.extractMessage(err));
        } finally {
            this.isLoadingLogs = false;
        }
    }

    async loadSections() {
        try {
            this.sectionOptions = await getSections();
        } catch (err) {
            // Non-fatal — picklist just stays empty, user can still type in user filter
            console.error('AdminTrackSetup: failed to load sections', err);
        }
    }

    computeDateRange() {
        if (this.logDateRange === 'custom') {
            return { sinceStr: this.customStartDate || null, untilStr: this.customEndDate || null };
        }

        const now   = new Date();
        const today = this.dateStr(now);

        switch (this.logDateRange) {
            case 'today':
                return { sinceStr: today, untilStr: today };

            case 'yesterday': {
                const y = new Date(now);
                y.setDate(now.getDate() - 1);
                const yStr = this.dateStr(y);
                return { sinceStr: yStr, untilStr: yStr };
            }
            case 'this_month': {
                const first = new Date(now.getFullYear(), now.getMonth(), 1);
                return { sinceStr: this.dateStr(first), untilStr: null };
            }
            case 'last_month': {
                const firstOfLast = new Date(now.getFullYear(), now.getMonth() - 1, 1);
                const lastOfLast  = new Date(now.getFullYear(), now.getMonth(), 0);
                return { sinceStr: this.dateStr(firstOfLast), untilStr: this.dateStr(lastOfLast) };
            }
            default: {
                // Numeric rolling window: '7', '30', '90', '180'
                const since = new Date(now);
                since.setDate(now.getDate() - parseInt(this.logDateRange, 10));
                return { sinceStr: this.dateStr(since), untilStr: null };
            }
        }
    }

    dateStr(date) {
        return date.toISOString().split('T')[0];
    }

    async refreshStatus() {
        this.isLoading = true;
        try {
            const data = await getJobStatus();
            this.applyJobStatus(data);
        } catch (err) {
            this.setError('Status refresh failed: ' + this.extractMessage(err));
        } finally {
            this.isLoading = false;
        }
    }

    applyJobStatus(data) {
        this.jobStatus     = data;
        this.scheduledJobs = data.scheduledJobs  || [];
        this.processorRuns = data.processorRuns  || [];
        if (data.intervalMinutes) {
            this.intervalMinutes = String(data.intervalMinutes);
        }
    }

    setError(message) {
        this.error          = true;
        this.errorMessage   = message;
        this.successMessage = '';
    }

    clearMessages() {
        this.error          = false;
        this.errorMessage   = '';
        this.successMessage = '';
    }

    extractMessage(err) {
        if (err && err.body && err.body.message) return err.body.message;
        if (err && err.message)                  return err.message;
        return JSON.stringify(err);
    }
}
