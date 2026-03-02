/**
 * SlackNotificationService
 * Sends one summary Slack notification per batch run via Incoming Webhook.
 * Must be called BEFORE any DML in the same transaction (callout-before-DML rule).
 *
 * SECURITY NOTE — Webhook URL Storage:
 * The Slack Incoming Webhook URL is stored in AdminTrackSettings__c (a Protected
 * Hierarchy Custom Setting) rather than a Named Credential. This is intentional:
 *
 *   - Slack Incoming Webhook URLs are org-specific tokens configured by the admin
 *     post-installation. Named Credentials require the endpoint to be declared at
 *     deployment time and do not support user-supplied, token-embedded URLs of
 *     this form (e.g., https://hooks.slack.com/services/T.../B.../...).
 *
 *   - The webhook URL is stored in a Protected Custom Setting, which restricts
 *     visibility to users with the "Customize Application" permission
 *     (i.e., org administrators only).
 *
 *   - All outbound callouts are restricted to https://hooks.slack.com/ at the
 *     platform level by the Remote Site Setting (Slack_Hooks), which enforces
 *     the domain allowlist independently of application logic.
 *
 *   - isValidWebhookUrl() validates the URL prefix before every callout,
 *     ensuring only legitimate Slack endpoints are called.
 */
public with sharing class SlackNotificationService {

    private static final String  VALID_WEBHOOK_PREFIX = 'https://hooks.slack.com/';
    private static final Integer CALLOUT_TIMEOUT_MS   = 10000;
    // Hard ceiling on outbound Slack messages per batch run (Apex allows max 100 callouts).
    private static final Integer MAX_SLACK_MESSAGES   = 50;

    /**
     * Sends one or more Slack messages for a completed batch run.
     * Changes are split across multiple messages (each up to SlackMaxDetails__c entries)
     * so no changes are silently omitted. Returns true only if all posts succeed.
     */
    public static Boolean sendSummary(
        Integer                   totalChanges,
        Integer                   excludedCount,
        DateTime                  windowStart,
        DateTime                  windowEnd,
        List<Map<String, String>> sampleChanges
    ) {
        AdminTrackSettings__c settings = AdminTrackSettings__c.getInstance();
        if (settings == null || !settings.SlackEnabled__c) {
            return false;
        }

        String webhookUrl = settings.SlackWebhookUrl__c;
        if (!isValidWebhookUrl(webhookUrl)) {
            System.debug(LoggingLevel.ERROR,
                'SlackNotificationService: invalid or missing webhook URL. Skipping notification.');
            return false;
        }

        List<String> payloads = buildSlackPayloads(
            totalChanges, excludedCount, windowStart, windowEnd, sampleChanges, settings
        );

        Boolean allSucceeded = true;
        for (String payload : payloads) {
            if (!postToSlack(webhookUrl, payload)) {
                allSucceeded = false;
            }
        }
        return allSucceeded;
    }

    /**
     * Builds the Slack JSON payload(s).
     * Custom template → always one message.
     * Default format  → one message per chunk of SlackMaxDetails__c changes (default 25),
     *                   capped at MAX_SLACK_MESSAGES total posts per run.
     * Tokens: {count}, {orgName}, {timestamp}
     */
    @TestVisible
    static String buildSlackMessage(
        Integer                   totalChanges,
        Integer                   excludedCount,
        DateTime                  windowStart,
        DateTime                  windowEnd,
        List<Map<String, String>> sampleChanges,
        AdminTrackSettings__c     settings
    ) {
        // Kept for test compatibility — returns only the first payload.
        List<String> payloads = buildSlackPayloads(
            totalChanges, excludedCount, windowStart, windowEnd, sampleChanges, settings
        );
        return payloads.isEmpty() ? '' : payloads[0];
    }

    private static List<String> buildSlackPayloads(
        Integer                   totalChanges,
        Integer                   excludedCount,
        DateTime                  windowStart,
        DateTime                  windowEnd,
        List<Map<String, String>> sampleChanges,
        AdminTrackSettings__c     settings
    ) {
        String template = (settings != null && !String.isBlank(settings.SlackMessageTemplate__c))
            ? settings.SlackMessageTemplate__c
            : null;

        if (template != null) {
            String messageText = template
                .replace('{count}',     String.valueOf(totalChanges))
                .replace('{orgName}',   UserInfo.getOrganizationName())
                .replace('{timestamp}', DateTime.now().format('yyyy-MM-dd HH:mm:ss z'));
            return new List<String>{
                JSON.serialize(new Map<String, Object>{ 'text' => messageText })
            };
        }

        Integer perMsg     = (settings != null && settings.SlackMaxDetails__c != null)
                                ? Math.max(1, (Integer) settings.SlackMaxDetails__c)
                                : 25;
        Integer sampleSize = sampleChanges != null ? sampleChanges.size() : 0;
        Integer totalPages = sampleSize == 0 ? 1 : (Integer) Math.ceil((Decimal) sampleSize / perMsg);
        Integer pagesToSend = Math.min(totalPages, MAX_SLACK_MESSAGES);
        Boolean truncated   = totalPages > MAX_SLACK_MESSAGES;

        String orgName  = UserInfo.getOrganizationName();
        String winStart = windowStart != null ? windowStart.format('yyyy-MM-dd HH:mm z') : '—';
        String winEnd   = windowEnd   != null ? windowEnd.format('yyyy-MM-dd HH:mm z')   : '—';

        List<String> payloads = new List<String>();
        for (Integer page = 0; page < pagesToSend; page++) {
            Integer startIdx   = page * perMsg;
            Integer endIdx     = Math.min(startIdx + perMsg, sampleSize);
            Boolean isFirst    = (page == 0);
            Boolean isLastPage = (page == pagesToSend - 1);

            List<String> lines = new List<String>();

            if (isFirst) {
                lines.add('*AdminTrack Alert* — ' + orgName);
                lines.add(totalChanges + ' new setup change' + (totalChanges == 1 ? '' : 's') + ' detected');
                lines.add('Period: ' + winStart + ' → ' + winEnd);
                if (excludedCount > 0) {
                    lines.add('(' + excludedCount + ' excluded by rules)');
                }
            } else {
                lines.add('*AdminTrack* _(continued)_');
            }
            if (pagesToSend > 1) {
                lines.add('_(Part ' + (page + 1) + ' of ' + pagesToSend + ')_');
            }
            lines.add('');

            if (sampleSize > 0) {
                for (Integer i = startIdx; i < endIdx; i++) {
                    Map<String, String> change = sampleChanges[i];
                    lines.add('• *' + safe(change.get('section')) + '* / ' + safe(change.get('action'))
                        + ' — ' + safe(change.get('display'))
                        + ' _(' + formatUser(change.get('username'), change.get('delegated')) + ')_');
                }
            }

            if (isLastPage) {
                // When the sample list was capped below totalChanges (e.g., MAX_SAMPLE_CHANGES
                // limit), note how many additional changes are not shown in the message.
                if (sampleSize < totalChanges) {
                    Integer remaining = totalChanges - sampleSize;
                    lines.add('');
                    lines.add('_(' + remaining + ' more change'
                        + (remaining == 1 ? '' : 's')
                        + ' not shown — view the full log in AdminTrack.)_');
                }
                if (truncated) {
                    lines.add('');
                    lines.add('_Message limit reached — see AdminTrack Audit Log for remaining changes._');
                }
            }

            payloads.add(JSON.serialize(new Map<String, Object>{ 'text' => String.join(lines, '\n') }));
        }
        return payloads;
    }

    private static String safe(String value) {
        return String.isBlank(value) ? '(unknown)' : value;
    }

    /**
     * Returns a user attribution string.
     * If delegated is non-blank and different from username, shows both:
     *   "username via delegated"
     * Otherwise just the username.
     */
    private static String formatUser(String username, String delegated) {
        String user = String.isBlank(username) ? '(unknown)' : username;
        if (!String.isBlank(delegated) && !delegated.equalsIgnoreCase(username)) {
            return user + ' via ' + delegated;
        }
        return user;
    }

    /**
     * Sends a one-time confirmation message to the channel when Slack is first enabled.
     * Runs asynchronously so it does not violate the callout-before-DML rule in
     * saveSlackSettings (which upserts settings before calling this).
     */
    @future(callout=true)
    public static void sendConfirmationAsync(String webhookUrl) {
        if (!isValidWebhookUrl(webhookUrl)) return;
        String payload = JSON.serialize(new Map<String, Object>{
            'text' => '*AdminTrack* connected successfully. Setup change alerts will be posted to this channel.'
        });
        postToSlack(webhookUrl, payload);
    }

    @TestVisible
    public static Boolean isValidWebhookUrl(String url) {
        return !String.isBlank(url) && url.startsWith(VALID_WEBHOOK_PREFIX);
    }

    private static Boolean postToSlack(String webhookUrl, String jsonPayload) {
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(webhookUrl);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setBody(jsonPayload);
            req.setTimeout(CALLOUT_TIMEOUT_MS);

            HttpResponse res = new Http().send(req);

            if (res.getStatusCode() == 200) {
                return true;
            }
            System.debug(LoggingLevel.ERROR,
                'SlackNotificationService: webhook returned HTTP ' + res.getStatusCode()
                + ' — ' + res.getBody());
            return false;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'SlackNotificationService: callout exception — ' + ex.getMessage());
            return false;
        }
    }
}
