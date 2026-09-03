public with sharing class ClmMetricsController {

    public class PresentationSummary {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public String formatType;
        @AuraEnabled public String productName;
        @AuraEnabled public String imageUrl;
        @AuraEnabled public Integer slideCount;
        @AuraEnabled public String tags;
    }

    public class PresentationPrefetch {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public String formatType;
        @AuraEnabled public String productName;
        @AuraEnabled public String imageUrl;
        @AuraEnabled public Integer slideCount;
        @AuraEnabled public String tags;
        @AuraEnabled public String contentDocumentId;
        @AuraEnabled public String contentVersionId;
        @AuraEnabled public Integer contentSize;
        @AuraEnabled public Datetime lastModifiedDate;
        @AuraEnabled public List<SequenceDetail> sequences;
    }

    public class SequenceDetail {
        @AuraEnabled public Id id;
        @AuraEnabled public Integer sequenceOrder;
        @AuraEnabled public String sequenceName;
        @AuraEnabled public String fileName;
        @AuraEnabled public String productNames;
        @AuraEnabled public String messageNames;
        @AuraEnabled public Boolean isMandatory;
        @AuraEnabled public String thumbnailUrl;
        @AuraEnabled public String slideImageUrl;
        @AuraEnabled public Integer pageNumber;
        @AuraEnabled public String htmlEntryPoint;
    }

    public class SessionSummary {
        @AuraEnabled public Id id;
        @AuraEnabled public Id visitId;
        @AuraEnabled public String name;
        @AuraEnabled public Id presentationId;
        @AuraEnabled public String presentationName;
        @AuraEnabled public String formatType;
        @AuraEnabled public String contentDocumentId;
        @AuraEnabled public String contentVersionId;
        @AuraEnabled public String publicContentUrl;
        @AuraEnabled public Integer contentSize;
        @AuraEnabled public String status;
        @AuraEnabled public Datetime startedAt;
        @AuraEnabled public Datetime endedAt;
        @AuraEnabled public Decimal totalDurationSeconds;
        @AuraEnabled public Decimal slidesPresentedCount;
        @AuraEnabled public Decimal slideCount;
        @AuraEnabled public Boolean trackingPaused;
        @AuraEnabled public String productName;
        @AuraEnabled public String productImageUrl;
        @AuraEnabled public List<SequenceDetail> sequences;
        @AuraEnabled public List<SlideMetricSummary> metrics;
    }

    public class SlideMetricSummary {
        @AuraEnabled public Id sequenceId;
        @AuraEnabled public Integer sequenceOrder;
        @AuraEnabled public String sequenceName;
        @AuraEnabled public Decimal dwellTimeSeconds;
        @AuraEnabled public Boolean wasPresented;
        @AuraEnabled public String thumbnailUrl;
    }

    public class MessageResponseInput {
        @AuraEnabled public String productName;
        @AuraEnabled public String messageName;
        @AuraEnabled public String sentiment;
        @AuraEnabled public Integer sortOrder;
    }

    public class VisitRatingFieldInput {
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String fieldApiName;
        @AuraEnabled public String valueJson;
    }

    public class VisitRatingContext {
        @AuraEnabled public Id accountId;
        @AuraEnabled public Id territory2Id;
        @AuraEnabled public String territoryName;
        @AuraEnabled public Id product2Id;
        @AuraEnabled public Id layoutId;
        @AuraEnabled public String layoutJson;
        @AuraEnabled public String valuesJson;
        @AuraEnabled public String accountVariant;
        @AuraEnabled public List<ProductRatingRow> alignedProducts;
    }

    public class ProductRatingRow {
        @AuraEnabled public Id product2Id;
        @AuraEnabled public String productName;
        @AuraEnabled public String imageUrl;
        @AuraEnabled public String valuesJson;
    }

    public class ProductRatingSaveInput {
        @AuraEnabled public Id product2Id;
        @AuraEnabled public List<VisitRatingFieldInput> values;
    }

    public class AdHocPresentationStart {
        @AuraEnabled public Id visitId;
    }

    public class RatingValidityResult {
        @AuraEnabled public Integer validityScore;
        @AuraEnabled public List<String> reasons;
        @AuraEnabled public String summary;
        @AuraEnabled public String source;
        @AuraEnabled public Boolean usedFallback;
        @AuraEnabled public String fallbackMessage;
    }

    @AuraEnabled(cacheable=false)
    public static List<PresentationSummary> getAvailablePresentations(Id visitId) {
        Date today = Date.today();
        List<CLM_Presentation__c> presentations = [
            SELECT Id, Name, Status__c, Format__c, Product__r.Name,
                   Slide_Count__c, Tags__c, Territory_Ids__c, Allow_Unaligned__c,
                   Start_Date__c, End_Date__c
            FROM CLM_Presentation__c
            WHERE Status__c = 'Available'
            WITH USER_MODE
            ORDER BY Name ASC
        ];

        List<PresentationSummary> results = new List<PresentationSummary>();
        for (CLM_Presentation__c pres : presentations) {
            if (!isPresentationInDateWindow(pres, today)) {
                continue;
            }
            if (!isPresentationAvailableForTerritories(pres)) {
                continue;
            }
            PresentationSummary summary = new PresentationSummary();
            summary.id = pres.Id;
            summary.name = pres.Name;
            summary.status = pres.Status__c;
            summary.formatType = pres.Format__c;
            summary.productName = pres.Product__r?.Name;
            summary.imageUrl = null;
            summary.slideCount = pres.Slide_Count__c != null ? Integer.valueOf(pres.Slide_Count__c) : 0;
            summary.tags = pres.Tags__c;
            results.add(summary);
        }
        return results;
    }

    @AuraEnabled(cacheable=false)
    public static List<PresentationSummary> getRepPresentations() {
        return getAvailablePresentations(null);
    }

    @AuraEnabled(cacheable=true)
    public static List<PresentationPrefetch> getRepPresentationManifest() {
        Date today = Date.today();
        List<CLM_Presentation__c> presentations = [
            SELECT Id, Name, Status__c, Format__c, Product__r.Name,
                   Slide_Count__c, Tags__c, Territory_Ids__c, Allow_Unaligned__c,
                   Start_Date__c, End_Date__c, Content_Document_Id__c, LastModifiedDate
            FROM CLM_Presentation__c
            WHERE Status__c = 'Available'
            WITH USER_MODE
            ORDER BY Name ASC
        ];

        List<PresentationPrefetch> results = new List<PresentationPrefetch>();
        for (CLM_Presentation__c pres : presentations) {
            if (!isPresentationInDateWindow(pres, today)) {
                continue;
            }
            if (!isPresentationAvailableForTerritories(pres)) {
                continue;
            }
            PresentationPrefetch prefetch = new PresentationPrefetch();
            prefetch.id = pres.Id;
            prefetch.name = pres.Name;
            prefetch.status = pres.Status__c;
            prefetch.formatType = pres.Format__c;
            prefetch.productName = pres.Product__r?.Name;
            prefetch.imageUrl = null;
            prefetch.slideCount = pres.Slide_Count__c != null ? Integer.valueOf(pres.Slide_Count__c) : 0;
            prefetch.tags = pres.Tags__c;
            prefetch.contentDocumentId = pres.Content_Document_Id__c;
            prefetch.lastModifiedDate = pres.LastModifiedDate;
            prefetch.sequences = getSequencesForPresentation(pres.Id);
            results.add(prefetch);
        }

        Map<Id, ContentVersion> versionsByDocument = new Map<Id, ContentVersion>();
        List<Id> docIds = new List<Id>(pluckContentDocumentIds(results));
        if (!docIds.isEmpty()) {
            for (ContentVersion version : [
                SELECT Id, ContentDocumentId, ContentSize
                FROM ContentVersion
                WHERE ContentDocumentId IN :docIds AND IsLatest = true
                WITH USER_MODE
            ]) {
                versionsByDocument.put(version.ContentDocumentId, version);
            }
            for (PresentationPrefetch prefetch : results) {
                ContentVersion version = versionsByDocument.get(prefetch.contentDocumentId);
                if (version != null) {
                    prefetch.contentVersionId = version.Id;
                    prefetch.contentSize = version.ContentSize != null
                        ? Integer.valueOf(version.ContentSize)
                        : null;
                }
            }
        }
        return results;
    }

    private static Set<Id> pluckContentDocumentIds(List<PresentationPrefetch> results) {
        Set<Id> ids = new Set<Id>();
        for (PresentationPrefetch prefetch : results) {
            if (String.isNotBlank(prefetch.contentDocumentId)) {
                ids.add((Id) prefetch.contentDocumentId);
            }
        }
        return ids;
    }

    @AuraEnabled
    public static AdHocPresentationStart startAdHocSession(Id presentationId) {
        SessionSummary session = startAdHocPresentation(presentationId);
        AdHocPresentationStart result = new AdHocPresentationStart();
        result.visitId = session.visitId;
        return result;
    }

    @AuraEnabled
    public static SessionSummary startAdHocPresentation(Id presentationId) {
        if (presentationId == null) {
            throw new AuraHandledException('Presentation is required.');
        }

        List<CLM_Presentation__c> presentations = [
            SELECT Id, Name, Slide_Count__c
            FROM CLM_Presentation__c
            WHERE Id = :presentationId AND Status__c = 'Available'
            WITH USER_MODE
            LIMIT 1
        ];
        if (presentations.isEmpty()) {
            throw new AuraHandledException('Presentation is not available.');
        }

        DateTime now = System.now();
        Visit__c visit = new Visit__c(
            Assigned_To__c = UserInfo.getUserId(),
            Start_Date__c = now,
            End_Date__c = now.addHours(1),
            Visit_Date__c = now,
            Status__c = 'Scheduled',
            Visit_Type__c = 'Unplanned'
        );
        insert as user visit;

        return createSessionForVisit(visit.Id, presentations[0]);
    }

    @AuraEnabled
    public static SessionSummary startSession(Id visitId, Id presentationId) {
        if (visitId == null || presentationId == null) {
            throw new AuraHandledException('Visit and presentation are required.');
        }

        Visit__c visit = [
            SELECT Id, Account__c, Status__c
            FROM Visit__c
            WHERE Id = :visitId
            WITH USER_MODE
            LIMIT 1
        ];
        if (visit.Status__c == 'Completed' || visit.Status__c == 'Cancelled') {
            throw new AuraHandledException('Cannot start CLM on a completed or cancelled visit.');
        }

        List<CLM_Presentation__c> presentations = [
            SELECT Id, Name, Slide_Count__c
            FROM CLM_Presentation__c
            WHERE Id = :presentationId AND Status__c = 'Available'
            WITH USER_MODE
            LIMIT 1
        ];
        if (presentations.isEmpty()) {
            throw new AuraHandledException('Presentation is not available.');
        }

        return createSessionForVisit(visit.Id, presentations[0]);
    }

    private static SessionSummary createSessionForVisit(Id visitId, CLM_Presentation__c presentation) {
        Visit__c visit = [
            SELECT Id, Account__c
            FROM Visit__c
            WHERE Id = :visitId
            WITH USER_MODE
            LIMIT 1
        ];

        CLM_Presentation_Session__c session = new CLM_Presentation_Session__c(
            Visit__c = visitId,
            CLM_Presentation__c = presentation.Id,
            Account__c = visit.Account__c,
            User__c = UserInfo.getUserId(),
            Status__c = 'Active',
            Started_At__c = System.now(),
            Tracking_Paused__c = false,
            Total_Duration_Seconds__c = 0,
            Slides_Presented_Count__c = 0
        );
        insert as user session;

        return getSessionDetail(session.Id, true);
    }

    @AuraEnabled
    public static void logSlideEvent(
        Id sessionId,
        Id sequenceId,
        Decimal dwellSeconds,
        Boolean trackingPaused
    ) {
        if (sessionId == null) {
            throw new AuraHandledException('Session is required.');
        }

        CLM_Presentation_Session__c session = [
            SELECT Id, Status__c
            FROM CLM_Presentation_Session__c
            WHERE Id = :sessionId
            WITH USER_MODE
            LIMIT 1
        ];
        if (session.Status__c == 'Completed' || session.Status__c == 'Cancelled') {
            throw new AuraHandledException('Session is already closed.');
        }

        if (sequenceId != null) {
            CLM_Sequence__c sequence = [
                SELECT Id, Sequence_Order__c, Sequence_Name__c, Name
                FROM CLM_Sequence__c
                WHERE Id = :sequenceId
                WITH USER_MODE
                LIMIT 1
            ];

            Decimal increment = dwellSeconds != null ? dwellSeconds : 0;
            List<CLM_Slide_Metric__c> existing = [
                SELECT Id, Dwell_Time_Seconds__c, First_Viewed_At__c
                FROM CLM_Slide_Metric__c
                WHERE CLM_Presentation_Session__c = :sessionId AND CLM_Sequence__c = :sequenceId
                WITH USER_MODE
                LIMIT 1
            ];

            Datetime now = System.now();
            if (existing.isEmpty()) {
                insert as user new CLM_Slide_Metric__c(
                    CLM_Presentation_Session__c = sessionId,
                    CLM_Sequence__c = sequenceId,
                    Sequence_Order__c = sequence.Sequence_Order__c,
                    Sequence_Name__c = String.isNotBlank(sequence.Sequence_Name__c)
                        ? sequence.Sequence_Name__c
                        : sequence.Name,
                    Dwell_Time_Seconds__c = increment,
                    First_Viewed_At__c = now,
                    Last_Viewed_At__c = now,
                    Was_Presented__c = increment > 0
                );
            } else {
                CLM_Slide_Metric__c metric = existing[0];
                metric.Dwell_Time_Seconds__c =
                    (metric.Dwell_Time_Seconds__c != null ? metric.Dwell_Time_Seconds__c : 0) + increment;
                metric.Last_Viewed_At__c = now;
                metric.Was_Presented__c = true;
                if (metric.First_Viewed_At__c == null) {
                    metric.First_Viewed_At__c = now;
                }
                update as user metric;
            }
        }

        session.Tracking_Paused__c = trackingPaused == true;
        session.Status__c = trackingPaused == true ? 'Paused' : 'Active';
        update as user session;

        refreshSessionTotals(sessionId);
    }

    @AuraEnabled
    public static SessionSummary completeSession(Id sessionId) {
        if (sessionId == null) {
            throw new AuraHandledException('Session Id is required.');
        }
        update as user new CLM_Presentation_Session__c(
            Id = sessionId,
            Status__c = 'Completed',
            Ended_At__c = System.now(),
            Tracking_Paused__c = false
        );
        refreshSessionTotals(sessionId);
        return getSessionDetail(sessionId);
    }

    @AuraEnabled
    public static void cancelSession(Id sessionId) {
        if (sessionId == null) {
            throw new AuraHandledException('Session Id is required.');
        }
        update as user new CLM_Presentation_Session__c(
            Id = sessionId,
            Status__c = 'Cancelled',
            Ended_At__c = System.now(),
            Tracking_Paused__c = false
        );
        refreshSessionTotals(sessionId);
    }

    @AuraEnabled
    public static void saveMessageResponses(Id sessionId, List<MessageResponseInput> responses) {
        if (sessionId == null) {
            throw new AuraHandledException('Session Id is required.');
        }
        if (responses == null || responses.isEmpty()) {
            return;
        }

        delete as user [
            SELECT Id
            FROM CLM_Message_Response__c
            WHERE CLM_Presentation_Session__c = :sessionId
            WITH USER_MODE
        ];

        List<CLM_Message_Response__c> rows = new List<CLM_Message_Response__c>();
        for (MessageResponseInput input : responses) {
            if (input == null || String.isBlank(input.messageName)) {
                continue;
            }
            rows.add(new CLM_Message_Response__c(
                CLM_Presentation_Session__c = sessionId,
                Product_Name__c = input.productName,
                Message_Name__c = input.messageName,
                Sentiment__c = input.sentiment,
                Sort_Order__c = input.sortOrder
            ));
        }
        if (!rows.isEmpty()) {
            insert as user rows;
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<MessageResponseInput> getSessionMessageResponses(Id sessionId) {
        List<MessageResponseInput> results = new List<MessageResponseInput>();
        if (sessionId == null) {
            return results;
        }
        for (CLM_Message_Response__c row : [
            SELECT Product_Name__c, Message_Name__c, Sentiment__c, Sort_Order__c
            FROM CLM_Message_Response__c
            WHERE CLM_Presentation_Session__c = :sessionId
            WITH USER_MODE
            ORDER BY Sort_Order__c ASC NULLS LAST
        ]) {
            MessageResponseInput input = new MessageResponseInput();
            input.productName = row.Product_Name__c;
            input.messageName = row.Message_Name__c;
            input.sentiment = row.Sentiment__c;
            input.sortOrder = row.Sort_Order__c != null ? Integer.valueOf(row.Sort_Order__c) : null;
            results.add(input);
        }
        return results;
    }

    @AuraEnabled(cacheable=true)
    public static List<SessionSummary> getVisitSessions(Id visitId) {
        if (visitId == null) {
            return new List<SessionSummary>();
        }
        List<CLM_Presentation_Session__c> sessions = [
            SELECT Id
            FROM CLM_Presentation_Session__c
            WHERE Visit__c = :visitId
            WITH USER_MODE
            ORDER BY Started_At__c DESC NULLS LAST
        ];
        List<SessionSummary> results = new List<SessionSummary>();
        for (CLM_Presentation_Session__c session : sessions) {
            results.add(getSessionDetail(session.Id));
        }
        return results;
    }

    @AuraEnabled(cacheable=true)
    public static SessionSummary getSessionDetail(Id sessionId) {
        return getSessionDetail(sessionId, true);
    }

    private static SessionSummary getSessionDetail(Id sessionId, Boolean includeMetrics) {
        CLM_Presentation_Session__c session = [
            SELECT Id, Name, Status__c, Started_At__c, Ended_At__c, Total_Duration_Seconds__c,
                   Slides_Presented_Count__c, Tracking_Paused__c, Visit__c,
                   CLM_Presentation__c, CLM_Presentation__r.Name, CLM_Presentation__r.Slide_Count__c,
                   CLM_Presentation__r.Format__c, CLM_Presentation__r.Content_Document_Id__c,
                   CLM_Presentation__r.Public_Content_URL__c, CLM_Presentation__r.Product__r.Name
            FROM CLM_Presentation_Session__c
            WHERE Id = :sessionId
            WITH USER_MODE
            LIMIT 1
        ];

        SessionSummary summary = new SessionSummary();
        summary.id = session.Id;
        summary.visitId = session.Visit__c;
        summary.name = session.Name;
        summary.presentationId = session.CLM_Presentation__c;
        summary.presentationName = session.CLM_Presentation__r?.Name;
        summary.formatType = session.CLM_Presentation__r?.Format__c;
        summary.contentDocumentId = session.CLM_Presentation__r?.Content_Document_Id__c;
        summary.publicContentUrl = session.CLM_Presentation__r?.Public_Content_URL__c;
        populateContentVersion(summary);
        summary.status = session.Status__c;
        summary.startedAt = session.Started_At__c;
        summary.endedAt = session.Ended_At__c;
        summary.totalDurationSeconds = session.Total_Duration_Seconds__c;
        summary.slidesPresentedCount = session.Slides_Presented_Count__c;
        summary.slideCount = session.CLM_Presentation__r?.Slide_Count__c;
        summary.trackingPaused = session.Tracking_Paused__c;
        summary.productName = session.CLM_Presentation__r?.Product__r?.Name;
        summary.productImageUrl = null;
        summary.sequences = getSequencesForPresentation(session.CLM_Presentation__c);
        summary.metrics = includeMetrics == true ? getSlideMetrics(sessionId) : new List<SlideMetricSummary>();
        return summary;
    }

    @AuraEnabled(cacheable=true)
    public static String getDeployedRatingLayoutJson() {
        return null;
    }

    @AuraEnabled(cacheable=true)
    public static VisitRatingContext getRatingCaptureContext(Id visitId, Id sessionId) {
        return mapServiceContext(ClmRatingLayoutService.buildCaptureContext(visitId, sessionId));
    }

    @AuraEnabled
    public static VisitRatingContext loadAccountRatingContext(Id accountId) {
        return mapServiceContext(ClmRatingLayoutService.buildAccountCaptureContext(accountId));
    }

    @AuraEnabled
    public static VisitRatingContext saveAccountRatings(
        Id accountId,
        Id layoutId,
        Id territory2Id,
        String fieldInputsJson,
        String productRatingsJson
    ) {
        List<VisitRatingFieldInput> values = parseFieldInputsJson(fieldInputsJson);
        List<ProductRatingSaveInput> productRatings = parseProductRatingsJson(productRatingsJson);
        List<ClmRatingLayoutService.VisitRatingFieldInput> serviceValues = toServiceFieldInputs(values);
        List<ClmRatingLayoutService.ProductRatingSaveInput> serviceProductRatings =
            toServiceProductRatings(productRatings);
        if (serviceValues.isEmpty() && serviceProductRatings.isEmpty()) {
            throw new AuraHandledException(
                'No valid rating fields were provided. Refresh the page and try again.'
            );
        }
        ClmRatingLayoutService.saveAccountRatings(
            accountId,
            layoutId,
            territory2Id,
            serviceValues,
            serviceProductRatings
        );
        return mapServiceContext(
            ClmRatingLayoutService.buildAccountCaptureContextAfterSave(accountId, territory2Id)
        );
    }

    private static VisitRatingContext mapServiceContext(
        ClmRatingLayoutService.VisitRatingContext serviceContext
    ) {
        VisitRatingContext context = new VisitRatingContext();
        if (serviceContext == null) {
            context.alignedProducts = new List<ProductRatingRow>();
            return context;
        }
        context.accountId = serviceContext.accountId;
        context.territory2Id = serviceContext.territory2Id;
        context.territoryName = serviceContext.territoryName;
        context.product2Id = serviceContext.product2Id;
        context.layoutId = serviceContext.layoutId;
        context.layoutJson = serviceContext.layoutJson;
        context.valuesJson = serviceContext.valuesJson;
        context.accountVariant = serviceContext.accountVariant;
        context.alignedProducts = new List<ProductRatingRow>();
        if (serviceContext.alignedProducts != null) {
            for (ClmRatingLayoutService.ProductRatingRow row : serviceContext.alignedProducts) {
                ProductRatingRow mappedRow = new ProductRatingRow();
                mappedRow.product2Id = row.product2Id;
                mappedRow.productName = row.productName;
                mappedRow.imageUrl = row.imageUrl;
                mappedRow.valuesJson = row.valuesJson;
                context.alignedProducts.add(mappedRow);
            }
        }
        return context;
    }

    private static List<VisitRatingFieldInput> parseFieldInputsJson(String fieldInputsJson) {
        List<VisitRatingFieldInput> parsed = new List<VisitRatingFieldInput>();
        if (String.isBlank(fieldInputsJson)) {
            return parsed;
        }
        Object raw = JSON.deserializeUntyped(fieldInputsJson);
        if (!(raw instanceof List<Object>)) {
            return parsed;
        }
        for (Object item : (List<Object>) raw) {
            if (!(item instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> row = (Map<String, Object>) item;
            String objectApiName = (String) row.get('objectApiName');
            String fieldApiName = (String) row.get('fieldApiName');
            if (String.isBlank(objectApiName) || String.isBlank(fieldApiName)) {
                continue;
            }
            VisitRatingFieldInput input = new VisitRatingFieldInput();
            input.objectApiName = objectApiName;
            input.fieldApiName = fieldApiName;
            Object valueJson = row.get('valueJson');
            input.valueJson = valueJson == null ? null : String.valueOf(valueJson);
            parsed.add(input);
        }
        return parsed;
    }

    private static List<ProductRatingSaveInput> parseProductRatingsJson(String productRatingsJson) {
        List<ProductRatingSaveInput> parsed = new List<ProductRatingSaveInput>();
        if (String.isBlank(productRatingsJson)) {
            return parsed;
        }
        Object raw = JSON.deserializeUntyped(productRatingsJson);
        if (!(raw instanceof List<Object>)) {
            return parsed;
        }
        for (Object item : (List<Object>) raw) {
            if (!(item instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> row = (Map<String, Object>) item;
            Object product2IdRaw = row.get('product2Id');
            if (product2IdRaw == null) {
                continue;
            }
            ProductRatingSaveInput productInput = new ProductRatingSaveInput();
            productInput.product2Id = (Id) String.valueOf(product2IdRaw);
            productInput.values = new List<VisitRatingFieldInput>();
            Object valuesRaw = row.get('values');
            if (valuesRaw instanceof List<Object>) {
                for (Object valueItem : (List<Object>) valuesRaw) {
                    if (!(valueItem instanceof Map<String, Object>)) {
                        continue;
                    }
                    Map<String, Object> valueRow = (Map<String, Object>) valueItem;
                    String objectApiName = (String) valueRow.get('objectApiName');
                    String fieldApiName = (String) valueRow.get('fieldApiName');
                    if (String.isBlank(objectApiName) || String.isBlank(fieldApiName)) {
                        continue;
                    }
                    VisitRatingFieldInput valueInput = new VisitRatingFieldInput();
                    valueInput.objectApiName = objectApiName;
                    valueInput.fieldApiName = fieldApiName;
                    Object valueJson = valueRow.get('valueJson');
                    valueInput.valueJson = valueJson == null ? null : String.valueOf(valueJson);
                    productInput.values.add(valueInput);
                }
            }
            if (!productInput.values.isEmpty()) {
                parsed.add(productInput);
            }
        }
        return parsed;
    }

    private static List<ClmRatingLayoutService.VisitRatingFieldInput> toServiceFieldInputs(
        List<VisitRatingFieldInput> values
    ) {
        List<ClmRatingLayoutService.VisitRatingFieldInput> serviceValues =
            new List<ClmRatingLayoutService.VisitRatingFieldInput>();
        if (values == null) {
            return serviceValues;
        }
        for (VisitRatingFieldInput input : values) {
            if (input == null || String.isBlank(input.objectApiName) || String.isBlank(input.fieldApiName)) {
                continue;
            }
            ClmRatingLayoutService.VisitRatingFieldInput row =
                new ClmRatingLayoutService.VisitRatingFieldInput();
            row.objectApiName = input.objectApiName;
            row.fieldApiName = input.fieldApiName;
            row.valueJson = input.valueJson;
            serviceValues.add(row);
        }
        return serviceValues;
    }

    private static List<ClmRatingLayoutService.ProductRatingSaveInput> toServiceProductRatings(
        List<ProductRatingSaveInput> productRatings
    ) {
        List<ClmRatingLayoutService.ProductRatingSaveInput> mapped =
            new List<ClmRatingLayoutService.ProductRatingSaveInput>();
        if (productRatings == null) {
            return mapped;
        }
        for (ProductRatingSaveInput productInput : productRatings) {
            if (productInput == null || productInput.product2Id == null) {
                continue;
            }
            ClmRatingLayoutService.ProductRatingSaveInput serviceProductInput =
                new ClmRatingLayoutService.ProductRatingSaveInput();
            serviceProductInput.product2Id = productInput.product2Id;
            serviceProductInput.values = toServiceFieldInputs(productInput.values);
            if (!serviceProductInput.values.isEmpty()) {
                mapped.add(serviceProductInput);
            }
        }
        return mapped;
    }

    @AuraEnabled
    public static RatingValidityResult validateAccountRatings(Id accountId, String liveRatingsJson) {
        RatingValidityResult result = new RatingValidityResult();
        result.validityScore = 0;
        result.reasons = new List<String>();
        result.summary = null;
        result.source = 'Fallback';
        result.usedFallback = true;
        result.fallbackMessage = 'Rating validity is not configured in this org.';
        return result;
    }

    @AuraEnabled
    public static void saveVisitRatings(
        Id visitId,
        Id sessionId,
        Id layoutId,
        List<VisitRatingFieldInput> values
    ) {
        // No-op stub: rating layout services are not deployed in this slim package.
    }

    private static List<SequenceDetail> getSequencesForPresentation(Id presentationId) {
        List<SequenceDetail> results = new List<SequenceDetail>();
        if (presentationId == null) {
            return results;
        }
        for (CLM_Sequence__c seq : [
            SELECT Id, Sequence_Order__c, Sequence_Name__c, Name, File_Name__c, Product_Names__c,
                   Message_Names__c, Is_Mandatory__c, Thumbnail_Content_Version_Id__c,
                   Slide_Image_URL__c, Page_Number__c, HTML_Entry_Point__c
            FROM CLM_Sequence__c
            WHERE CLM_Presentation__c = :presentationId
            WITH USER_MODE
            ORDER BY Sequence_Order__c ASC NULLS LAST
        ]) {
            results.add(mapSequence(seq));
        }
        return results;
    }

    private static void populateContentVersion(SessionSummary summary) {
        if (String.isBlank(summary.contentDocumentId)) {
            return;
        }
        List<ContentVersion> versions = [
            SELECT Id, ContentSize
            FROM ContentVersion
            WHERE ContentDocumentId = :summary.contentDocumentId AND IsLatest = true
            WITH USER_MODE
            LIMIT 1
        ];
        if (versions.isEmpty()) {
            return;
        }
        summary.contentVersionId = versions[0].Id;
        summary.contentSize = versions[0].ContentSize != null
            ? Integer.valueOf(versions[0].ContentSize)
            : null;
    }

    private static SequenceDetail mapSequence(CLM_Sequence__c seq) {
        SequenceDetail detail = new SequenceDetail();
        detail.id = seq.Id;
        detail.sequenceOrder = seq.Sequence_Order__c != null ? Integer.valueOf(seq.Sequence_Order__c) : null;
        detail.sequenceName = String.isNotBlank(seq.Sequence_Name__c) ? seq.Sequence_Name__c : seq.Name;
        detail.fileName = seq.File_Name__c;
        detail.productNames = seq.Product_Names__c;
        detail.messageNames = seq.Message_Names__c;
        detail.isMandatory = seq.Is_Mandatory__c == true;
        detail.pageNumber = seq.Page_Number__c != null ? Integer.valueOf(seq.Page_Number__c) : null;
        detail.htmlEntryPoint = seq.HTML_Entry_Point__c;
        detail.slideImageUrl = ClmContentService.normalizeContentUrl(seq.Slide_Image_URL__c);
        detail.thumbnailUrl = ClmContentService.buildContentUrl(
            seq.Thumbnail_Content_Version_Id__c,
            seq.Slide_Image_URL__c
        );
        return detail;
    }

    private static List<SlideMetricSummary> getSlideMetrics(Id sessionId) {
        List<SlideMetricSummary> results = new List<SlideMetricSummary>();
        for (CLM_Slide_Metric__c metric : [
            SELECT Sequence_Order__c, Sequence_Name__c, Dwell_Time_Seconds__c, Was_Presented__c,
                   CLM_Sequence__c, CLM_Sequence__r.Thumbnail_Content_Version_Id__c,
                   CLM_Sequence__r.Slide_Image_URL__c
            FROM CLM_Slide_Metric__c
            WHERE CLM_Presentation_Session__c = :sessionId
            WITH USER_MODE
            ORDER BY Sequence_Order__c ASC NULLS LAST
        ]) {
            SlideMetricSummary summary = new SlideMetricSummary();
            summary.sequenceId = metric.CLM_Sequence__c;
            summary.sequenceOrder = metric.Sequence_Order__c != null
                ? Integer.valueOf(metric.Sequence_Order__c)
                : null;
            summary.sequenceName = metric.Sequence_Name__c;
            summary.dwellTimeSeconds = metric.Dwell_Time_Seconds__c;
            summary.wasPresented = metric.Was_Presented__c == true;
            summary.thumbnailUrl = ClmContentService.buildContentUrl(
                metric.CLM_Sequence__r?.Thumbnail_Content_Version_Id__c,
                metric.CLM_Sequence__r?.Slide_Image_URL__c
            );
            results.add(summary);
        }
        return results;
    }

    private static void refreshSessionTotals(Id sessionId) {
        AggregateResult[] totals = [
            SELECT SUM(Dwell_Time_Seconds__c) totalSeconds, COUNT(Id) metricCount
            FROM CLM_Slide_Metric__c
            WHERE CLM_Presentation_Session__c = :sessionId AND Was_Presented__c = TRUE
            WITH USER_MODE
        ];
        Decimal totalSeconds = 0;
        Decimal presentedCount = 0;
        if (!totals.isEmpty()) {
            totalSeconds = (Decimal) totals[0].get('totalSeconds');
            if (totalSeconds == null) {
                totalSeconds = 0;
            }
            presentedCount = (Decimal) totals[0].get('metricCount');
            if (presentedCount == null) {
                presentedCount = 0;
            }
        }
        update as user new CLM_Presentation_Session__c(
            Id = sessionId,
            Total_Duration_Seconds__c = totalSeconds,
            Slides_Presented_Count__c = presentedCount
        );
    }

    private static Boolean isPresentationInDateWindow(CLM_Presentation__c pres, Date today) {
        if (pres.Start_Date__c != null && today < pres.Start_Date__c) {
            return false;
        }
        if (pres.End_Date__c != null && today > pres.End_Date__c) {
            return false;
        }
        return true;
    }

    private static Boolean isPresentationAvailableForTerritories(CLM_Presentation__c pres) {
        // Slim filter: include when unaligned is allowed or no territory targeting is set.
        // Skip complex UserTerritory2Association / Territory2 hierarchy expansion.
        if (pres.Allow_Unaligned__c == true) {
            return true;
        }
        return String.isBlank(pres.Territory_Ids__c);
    }
}