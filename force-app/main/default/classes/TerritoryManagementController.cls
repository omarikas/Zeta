public without sharing class TerritoryManagementController {

    public class TerritoryAssignment {
        @AuraEnabled public Id associationId;
        @AuraEnabled public Id userId;
        @AuraEnabled public String userName;
        @AuraEnabled public String role;
    }

    public class TerritoryTreeNode {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String externalId;
        @AuraEnabled public String level;
        @AuraEnabled public Id parentId;
        @AuraEnabled public Boolean hasChildren;
        @AuraEnabled public Boolean isVacant;
        @AuraEnabled public Boolean canEdit;
        @AuraEnabled public Boolean canDelete;
        @AuraEnabled public Boolean canAddChild;
        @AuraEnabled public List<TerritoryAssignment> assignments;
        @AuraEnabled public List<TerritoryTreeNode> children;
    }

    public class UserOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String firstName;
        @AuraEnabled public String lastName;
        @AuraEnabled public String email;
        @AuraEnabled public String username;
        @AuraEnabled public String title;
        @AuraEnabled public String businessUnit;
        @AuraEnabled public String profileName;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Boolean isSystemAdmin;
        @AuraEnabled public Boolean canDeactivate;
        @AuraEnabled public String label;
    }

    public class UserProfileForm {
        @AuraEnabled public Id userId;
        @AuraEnabled public String firstName;
        @AuraEnabled public String lastName;
        @AuraEnabled public String email;
        @AuraEnabled public String username;
        @AuraEnabled public String title;
        @AuraEnabled public String department;
    }

    public class PasswordSetResult {
        @AuraEnabled public Integer successCount;
        @AuraEnabled public Integer failureCount;
        @AuraEnabled public String passwordUsed;
        @AuraEnabled public List<String> messages;
    }

    public class UserStatusResult {
        @AuraEnabled public Integer successCount;
        @AuraEnabled public Integer skippedCount;
        @AuraEnabled public Integer failureCount;
        @AuraEnabled public List<String> messages;
    }

    public class LineSummary {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String externalId;
        @AuraEnabled public String therapyArea;
        @AuraEnabled public Integer districtCount;
        @AuraEnabled public Integer repCount;
        @AuraEnabled public Integer productCount;
        @AuraEnabled public Integer brandCount;
        @AuraEnabled public Integer detailCount;
        @AuraEnabled public Integer sampleCount;
        @AuraEnabled public Integer reminderCount;
        @AuraEnabled public Boolean isProtected;
    }

    public class LineProductRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String productCode;
        @AuraEnabled public String productType;
        @AuraEnabled public String primaryBrand;
        @AuraEnabled public String salesLine;
        @AuraEnabled public String mirrorLine;
        @AuraEnabled public String salesUnit;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public String parentName;
        @AuraEnabled public Boolean matchedViaMirror;
    }

    public class ParentOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String label;
        @AuraEnabled public String level;
    }

    public class TerritoryForm {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String name;
        @AuraEnabled public String externalId;
        @AuraEnabled public Id parentId;
        @AuraEnabled public String level;
    }

    public class CreatedUserResult {
        @AuraEnabled public Id userId;
        @AuraEnabled public String username;
        @AuraEnabled public String message;
    }

    @AuraEnabled(cacheable=true)
    public static List<LineSummary> getProductLines() {
        String pharmaPrefix = 'TERR_%';
        List<Territory2> lines = [
            SELECT Id, Name, External_ID__c, Territory_Type__c
            FROM Territory2
            WHERE External_ID__c LIKE :pharmaPrefix
                AND Territory_Type__c = 'Line'
            WITH SYSTEM_MODE
            ORDER BY Name ASC
            LIMIT 500
        ];

        Map<Id, Integer> districtCountByLine = new Map<Id, Integer>();
        Map<Id, Integer> repCountByLine = new Map<Id, Integer>();
        if (!lines.isEmpty()) {
            Set<Id> lineIds = new Map<Id, Territory2>(lines).keySet();
            List<Territory2> districts = [
                SELECT Id, ParentTerritory2Id
                FROM Territory2
                WHERE ParentTerritory2Id IN :lineIds
                    AND Territory_Type__c = 'District'
                WITH SYSTEM_MODE
            ];
            Set<Id> districtIds = new Set<Id>();
            Map<Id, Id> lineByDistrict = new Map<Id, Id>();
            for (Territory2 district : districts) {
                Integer current = districtCountByLine.containsKey(district.ParentTerritory2Id)
                    ? districtCountByLine.get(district.ParentTerritory2Id)
                    : 0;
                districtCountByLine.put(district.ParentTerritory2Id, current + 1);
                districtIds.add(district.Id);
                lineByDistrict.put(district.Id, district.ParentTerritory2Id);
            }
            if (!districtIds.isEmpty()) {
                for (Territory2 position : [
                    SELECT Id, ParentTerritory2Id
                    FROM Territory2
                    WHERE ParentTerritory2Id IN :districtIds
                        AND Territory_Type__c = 'Position'
                    WITH SYSTEM_MODE
                ]) {
                    Id lineId = lineByDistrict.get(position.ParentTerritory2Id);
                    if (lineId == null) {
                        continue;
                    }
                    Integer current = repCountByLine.containsKey(lineId) ? repCountByLine.get(lineId) : 0;
                    repCountByLine.put(lineId, current + 1);
                }
            }
        }

        Map<String, List<Id>> lineIdsByKey = new Map<String, List<Id>>();
        for (Territory2 line : lines) {
            Set<String> keys = buildLineMatchKeys(line.Name, line.External_ID__c);
            for (String key : keys) {
                if (!lineIdsByKey.containsKey(key)) {
                    lineIdsByKey.put(key, new List<Id>());
                }
                lineIdsByKey.get(key).add(line.Id);
            }
        }

        Map<Id, Integer> productCountByLine = new Map<Id, Integer>();
        Map<Id, Integer> brandCountByLine = new Map<Id, Integer>();
        Map<Id, Integer> detailCountByLine = new Map<Id, Integer>();
        Map<Id, Integer> sampleCountByLine = new Map<Id, Integer>();
        Map<Id, Integer> reminderCountByLine = new Map<Id, Integer>();
        Map<Id, Map<String, Integer>> unitVotesByLine = new Map<Id, Map<String, Integer>>();

        if (!lines.isEmpty()) {
            for (Product2 product : [
                SELECT Id, Product_Type__c, Sales_Line__c, Mirror_Line__c, Sales_Unit__c, IsActive
                FROM Product2
                WHERE IsActive = TRUE
                    AND (
                        (Sales_Line__c != NULL AND Sales_Line__c != '')
                        OR (Mirror_Line__c != NULL AND Mirror_Line__c != '')
                    )
                WITH SYSTEM_MODE
                LIMIT 10000
            ]) {
                String salesKey = normalizeLineKey(product.Sales_Line__c);
                String mirrorKey = normalizeLineKey(product.Mirror_Line__c);
                if (isNonPromotedKey(salesKey) && isNonPromotedKey(mirrorKey)) {
                    continue;
                }
                Set<Id> matchedLineIds = new Set<Id>();
                if (String.isNotBlank(salesKey) && lineIdsByKey.containsKey(salesKey)) {
                    matchedLineIds.addAll(lineIdsByKey.get(salesKey));
                }
                if (String.isNotBlank(mirrorKey) && lineIdsByKey.containsKey(mirrorKey)) {
                    matchedLineIds.addAll(lineIdsByKey.get(mirrorKey));
                }
                for (Id lineId : matchedLineIds) {
                    incrementCount(productCountByLine, lineId);
                    String productType = product.Product_Type__c;
                    if (productType == 'Brand') {
                        incrementCount(brandCountByLine, lineId);
                    } else if (productType == 'Detail') {
                        incrementCount(detailCountByLine, lineId);
                    } else if (productType == 'Sample') {
                        incrementCount(sampleCountByLine, lineId);
                    } else if (productType == 'Brand Reminder') {
                        incrementCount(reminderCountByLine, lineId);
                    }
                    if (String.isNotBlank(product.Sales_Unit__c)
                        && !isNonPromotedKey(normalizeLineKey(product.Sales_Unit__c))) {
                        if (!unitVotesByLine.containsKey(lineId)) {
                            unitVotesByLine.put(lineId, new Map<String, Integer>());
                        }
                        Map<String, Integer> votes = unitVotesByLine.get(lineId);
                        String unit = product.Sales_Unit__c.trim();
                        votes.put(unit, (votes.containsKey(unit) ? votes.get(unit) : 0) + 1);
                    }
                }
            }
        }

        List<LineSummary> summaries = new List<LineSummary>();
        for (Territory2 line : lines) {
            LineSummary summary = new LineSummary();
            summary.id = line.Id;
            summary.name = line.Name;
            summary.externalId = line.External_ID__c;
            summary.therapyArea = dominantUnit(unitVotesByLine.get(line.Id));
            summary.districtCount = districtCountByLine.containsKey(line.Id)
                ? districtCountByLine.get(line.Id)
                : 0;
            summary.repCount = repCountByLine.containsKey(line.Id) ? repCountByLine.get(line.Id) : 0;
            summary.productCount = productCountByLine.containsKey(line.Id)
                ? productCountByLine.get(line.Id)
                : 0;
            summary.brandCount = brandCountByLine.containsKey(line.Id) ? brandCountByLine.get(line.Id) : 0;
            summary.detailCount = detailCountByLine.containsKey(line.Id) ? detailCountByLine.get(line.Id) : 0;
            summary.sampleCount = sampleCountByLine.containsKey(line.Id) ? sampleCountByLine.get(line.Id) : 0;
            summary.reminderCount = reminderCountByLine.containsKey(line.Id)
                ? reminderCountByLine.get(line.Id)
                : 0;
            summary.isProtected = false;
            summaries.add(summary);
        }
        return summaries;
    }

    @AuraEnabled(cacheable=true)
    public static List<LineProductRow> getProductsForLine(Id lineTerritoryId) {
        Territory2 line = requireLineTerritory(lineTerritoryId);
        Set<String> keys = buildLineMatchKeys(line.Name, line.External_ID__c);
        List<LineProductRow> rows = new List<LineProductRow>();
        for (Product2 product : [
            SELECT
                Id,
                Name,
                ProductCode,
                Product_Type__c,
                Primary_Brand__c,
                Sales_Line__c,
                Mirror_Line__c,
                Sales_Unit__c,
                IsActive,
                Parent_Product__r.Name
            FROM Product2
            WHERE
                (Sales_Line__c != NULL AND Sales_Line__c != '')
                OR (Mirror_Line__c != NULL AND Mirror_Line__c != '')
            WITH SYSTEM_MODE
            ORDER BY Product_Type__c ASC, Name ASC
            LIMIT 5000
        ]) {
            String salesKey = normalizeLineKey(product.Sales_Line__c);
            String mirrorKey = normalizeLineKey(product.Mirror_Line__c);
            Boolean matchedSales = String.isNotBlank(salesKey) && keys.contains(salesKey);
            Boolean matchedMirror = String.isNotBlank(mirrorKey) && keys.contains(mirrorKey);
            if (!matchedSales && !matchedMirror) {
                continue;
            }
            rows.add(toLineProductRow(product, matchedMirror && !matchedSales));
        }
        return rows;
    }

    @AuraEnabled(cacheable=true)
    public static List<LineProductRow> searchAssignableProducts(Id lineTerritoryId, String searchTerm) {
        Territory2 line = requireLineTerritory(lineTerritoryId);
        Set<String> keys = buildLineMatchKeys(line.Name, line.External_ID__c);
        String term = String.isBlank(searchTerm) ? null : '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';

        String soql =
            'SELECT Id, Name, ProductCode, Product_Type__c, Primary_Brand__c, Sales_Line__c,'
            + ' Mirror_Line__c, Sales_Unit__c, IsActive, Parent_Product__r.Name'
            + ' FROM Product2 WHERE IsActive = TRUE';
        if (term != null) {
            soql +=
                ' AND (Name LIKE :term OR ProductCode LIKE :term OR Primary_Brand__c LIKE :term'
                + ' OR Sales_Line__c LIKE :term OR Mirror_Line__c LIKE :term)';
        }
        soql += ' WITH SYSTEM_MODE ORDER BY Name ASC LIMIT 100';

        List<LineProductRow> rows = new List<LineProductRow>();
        for (Product2 product : Database.query(soql)) {
            String salesKey = normalizeLineKey(product.Sales_Line__c);
            String mirrorKey = normalizeLineKey(product.Mirror_Line__c);
            if ((String.isNotBlank(salesKey) && keys.contains(salesKey))
                || (String.isNotBlank(mirrorKey) && keys.contains(mirrorKey))) {
                continue;
            }
            rows.add(toLineProductRow(product, false));
        }
        return rows;
    }

    @AuraEnabled
    public static void setProductLineAssignment(Id productId, Id lineTerritoryId, Boolean asMirror) {
        if (productId == null) {
            throw new AuraHandledException('Product is required.');
        }
        Territory2 line = requireLineTerritory(lineTerritoryId);
        String lineLabel = preferredLineLabel(line);
        Product2 product = [
            SELECT Id, Sales_Line__c, Mirror_Line__c
            FROM Product2
            WHERE Id = :productId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (asMirror == true) {
            product.Mirror_Line__c = lineLabel;
        } else {
            product.Sales_Line__c = lineLabel;
        }
        try {
            update as system product;
        } catch (DmlException ex) {
            throw new AuraHandledException(ex.getDmlMessage(0));
        }
    }

    @AuraEnabled
    public static void clearProductLineAssignment(Id productId, Id lineTerritoryId) {
        if (productId == null || lineTerritoryId == null) {
            throw new AuraHandledException('Product and line are required.');
        }
        Territory2 line = requireLineTerritory(lineTerritoryId);
        Set<String> keys = buildLineMatchKeys(line.Name, line.External_ID__c);
        Product2 product = [
            SELECT Id, Sales_Line__c, Mirror_Line__c
            FROM Product2
            WHERE Id = :productId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        Boolean changed = false;
        if (keys.contains(normalizeLineKey(product.Sales_Line__c))) {
            product.Sales_Line__c = null;
            changed = true;
        }
        if (keys.contains(normalizeLineKey(product.Mirror_Line__c))) {
            product.Mirror_Line__c = null;
            changed = true;
        }
        if (!changed) {
            return;
        }
        try {
            update as system product;
        } catch (DmlException ex) {
            throw new AuraHandledException(ex.getDmlMessage(0));
        }
    }

    private static Territory2 requireLineTerritory(Id lineTerritoryId) {
        if (lineTerritoryId == null) {
            throw new AuraHandledException('Line territory is required.');
        }
        List<Territory2> lines = [
            SELECT Id, Name, External_ID__c, Territory_Type__c
            FROM Territory2
            WHERE Id = :lineTerritoryId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (lines.isEmpty()) {
            throw new AuraHandledException('Line territory not found.');
        }
        Territory2 line = lines[0];
        if (line.Territory_Type__c != 'Line') {
            throw new AuraHandledException('Selected territory is not a product line.');
        }
        return line;
    }

    private static LineProductRow toLineProductRow(Product2 product, Boolean matchedViaMirror) {
        LineProductRow row = new LineProductRow();
        row.id = product.Id;
        row.name = product.Name;
        row.productCode = product.ProductCode;
        row.productType = product.Product_Type__c;
        row.primaryBrand = product.Primary_Brand__c;
        row.salesLine = product.Sales_Line__c;
        row.mirrorLine = product.Mirror_Line__c;
        row.salesUnit = product.Sales_Unit__c;
        row.isActive = product.IsActive;
        row.parentName = product.Parent_Product__r != null ? product.Parent_Product__r.Name : null;
        row.matchedViaMirror = matchedViaMirror;
        return row;
    }

    private static Set<String> buildLineMatchKeys(String name, String externalId) {
        Set<String> keys = new Set<String>();
        addNormalizedKey(keys, name);
        if (String.isNotBlank(externalId)) {
            String ext = externalId.trim();
            if (ext.toUpperCase().startsWith('TERR_LINE_')) {
                addNormalizedKey(keys, ext.substring('TERR_LINE_'.length()));
            }
            addNormalizedKey(keys, ext);
        }
        return keys;
    }

    private static void addNormalizedKey(Set<String> keys, String raw) {
        String normalized = normalizeLineKey(raw);
        if (String.isNotBlank(normalized) && !isNonPromotedKey(normalized)) {
            keys.add(normalized);
        }
    }

    private static String normalizeLineKey(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        String value = raw.trim().toUpperCase();
        value = value.replaceAll('[\\s\\-]+', '_');
        value = value.replaceAll('_+', '_');
        return value;
    }

    private static Boolean isNonPromotedKey(String key) {
        return key == 'NON_PROMOTED' || key == 'NONPROMOTED';
    }

    private static String preferredLineLabel(Territory2 line) {
        if (String.isNotBlank(line.Name)) {
            return line.Name.trim();
        }
        if (String.isNotBlank(line.External_ID__c)
            && line.External_ID__c.toUpperCase().startsWith('TERR_LINE_')) {
            return line.External_ID__c.substring('TERR_LINE_'.length()).replace('_', '-');
        }
        return line.External_ID__c;
    }

    private static void incrementCount(Map<Id, Integer> counts, Id key) {
        counts.put(key, (counts.containsKey(key) ? counts.get(key) : 0) + 1);
    }

    private static String dominantUnit(Map<String, Integer> votes) {
        if (votes == null || votes.isEmpty()) {
            return null;
        }
        String best = null;
        Integer bestCount = -1;
        for (String unit : votes.keySet()) {
            Integer count = votes.get(unit);
            if (count > bestCount || (count == bestCount && (best == null || unit < best))) {
                best = unit;
                bestCount = count;
            }
        }
        return best;
    }

    @AuraEnabled(cacheable=true)
    public static List<ParentOption> getParentOptions(String childLevel) {
        String pharmaPrefix = 'TERR_%';
        List<ParentOption> options = new List<ParentOption>();
        String parentType;
        String parentLevelLabel;
        if (childLevel == 'Business Unit' || childLevel == 'Business_Unit') {
            parentType = 'Head_Office';
            parentLevelLabel = 'Head Office';
        } else if (childLevel == 'Line') {
            parentType = 'Business_Unit';
            parentLevelLabel = 'Business Unit';
        } else if (childLevel == 'District') {
            parentType = 'Line';
            parentLevelLabel = 'Line';
        } else if (childLevel == 'MR' || childLevel == 'Position') {
            parentType = 'District';
            parentLevelLabel = 'District';
        } else {
            return options;
        }

        for (Territory2 territory : [
            SELECT Id, Name
            FROM Territory2
            WHERE Territory_Type__c = :parentType
                AND External_ID__c LIKE :pharmaPrefix
            WITH SYSTEM_MODE
            ORDER BY Name ASC
            LIMIT 2000
        ]) {
            ParentOption option = new ParentOption();
            option.id = territory.Id;
            option.label = territory.Name;
            option.level = parentLevelLabel;
            options.add(option);
        }
        return options;
    }

    @AuraEnabled
    public static Id saveTerritory(TerritoryForm form) {
        if (form == null || String.isBlank(form.name)) {
            throw new AuraHandledException('Territory name is required.');
        }
        if (form.recordId != null) {
            Territory2 territory = [
                SELECT Id, Name, External_ID__c
                FROM Territory2
                WHERE Id = :form.recordId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (territory.External_ID__c == 'TERR_HEAD_OFFICE') {
                throw new AuraHandledException('Head Office cannot be edited.');
            }
            territory.Name = form.name.trim();
            if (form.parentId != null) {
                territory.ParentTerritory2Id = form.parentId;
            }
            update as system territory;
            return territory.Id;
        }
        throw new AuraHandledException(
            'Create new territories from Setup > Territory Models, or re-run the organogram loader.'
        );
    }

    @AuraEnabled
    public static Id createProductLine(String name, String code, String therapyArea) {
        throw new AuraHandledException(
            'Product lines are managed from the organogram load. Use Setup > Territory Models to add nodes.'
        );
    }

    @AuraEnabled
    public static void deleteTerritory(Id territoryId) {
        if (territoryId == null) {
            throw new AuraHandledException('Territory Id is required.');
        }
        Territory2 territory = [
            SELECT Id, External_ID__c
            FROM Territory2
            WHERE Id = :territoryId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (territory.External_ID__c == 'TERR_HEAD_OFFICE') {
            throw new AuraHandledException('Head Office cannot be deleted.');
        }
        Integer childCount = [
            SELECT COUNT()
            FROM Territory2
            WHERE ParentTerritory2Id = :territoryId
            WITH SYSTEM_MODE
        ];
        if (childCount > 0) {
            throw new AuraHandledException('Remove child territories before deleting this node.');
        }
        delete as system [
            SELECT Id
            FROM UserTerritory2Association
            WHERE Territory2Id = :territoryId
            WITH SYSTEM_MODE
        ];
        throw new AuraHandledException(
            'Assignments cleared. Delete the territory node in Setup > Territory Models.'
        );
    }

    @AuraEnabled
    public static CreatedUserResult createPharmaUser(
        String firstName,
        String lastName,
        String teamCode,
        String roleKey,
        Id territoryId,
        String roleInTerritory
    ) {
        throw new AuraHandledException(
            'Create users in Setup, then assign them from the Territories tab.'
        );
    }

    @AuraEnabled
    public static void syncDefaultLineProductAlignments() {
        // No-op on production organogram orgs.
    }

    @AuraEnabled(cacheable=true)
    public static List<TerritoryTreeNode> getTerritoryTree() {
        String pharmaPrefix = 'TERR_%';
        List<Territory2> territories = [
            SELECT Id, Name, ParentTerritory2Id, External_ID__c, Territory_Type__c
            FROM Territory2
            WHERE External_ID__c LIKE :pharmaPrefix
            WITH SYSTEM_MODE
            ORDER BY Name ASC
            LIMIT 5000
        ];
        if (territories.isEmpty()) {
            return new List<TerritoryTreeNode>();
        }

        Set<Id> territoryIds = new Map<Id, Territory2>(territories).keySet();
        Map<Id, List<TerritoryAssignment>> assignmentsByTerritory = loadAssignments(territoryIds);
        Map<Id, List<TerritoryTreeNode>> childrenByParent = new Map<Id, List<TerritoryTreeNode>>();
        Map<Id, TerritoryTreeNode> nodesById = new Map<Id, TerritoryTreeNode>();
        Set<Id> childParentIds = new Set<Id>();

        for (Territory2 territory : territories) {
            TerritoryTreeNode node = buildNode(territory, assignmentsByTerritory.get(territory.Id));
            nodesById.put(territory.Id, node);
            if (territory.ParentTerritory2Id != null) {
                childParentIds.add(territory.ParentTerritory2Id);
                if (!childrenByParent.containsKey(territory.ParentTerritory2Id)) {
                    childrenByParent.put(territory.ParentTerritory2Id, new List<TerritoryTreeNode>());
                }
                childrenByParent.get(territory.ParentTerritory2Id).add(node);
            }
        }

        for (Id parentId : childrenByParent.keySet()) {
            if (nodesById.containsKey(parentId)) {
                nodesById.get(parentId).children = childrenByParent.get(parentId);
                nodesById.get(parentId).hasChildren = !childrenByParent.get(parentId).isEmpty();
            }
        }

        List<TerritoryTreeNode> roots = new List<TerritoryTreeNode>();
        for (Territory2 territory : territories) {
            TerritoryTreeNode node = nodesById.get(territory.Id);
            if (node.hasChildren == null) {
                node.hasChildren = false;
                node.children = new List<TerritoryTreeNode>();
            }
            if (territory.ParentTerritory2Id == null || !nodesById.containsKey(territory.ParentTerritory2Id)) {
                roots.add(node);
            }
        }

        roots.sort(new TerritoryNodeNameComparator());
        sortChildrenRecursively(roots);
        return roots;
    }

    @AuraEnabled(cacheable=true)
    public static List<UserOption> getAssignableUsers(String searchTerm) {
        return getManagedUsers(searchTerm, false);
    }

    @AuraEnabled(cacheable=true)
    public static List<UserOption> getManagedUsers(String searchTerm, Boolean includeInactive) {
        String term = String.isBlank(searchTerm) ? null : '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
        Boolean showInactive = includeInactive == true;
        String soql =
            'SELECT Id, Name, FirstName, LastName, Email, Username, Title, Department, Division,'
            + ' IsActive, Profile.Name'
            + ' FROM User WHERE Username LIKE \'%pharma%\'';
        if (!showInactive) {
            soql += ' AND IsActive = TRUE';
        }
        if (term != null) {
            soql += ' AND (Name LIKE :term OR Username LIKE :term OR Email LIKE :term OR Title LIKE :term'
                + ' OR Department LIKE :term OR Division LIKE :term OR FirstName LIKE :term OR LastName LIKE :term)';
        }
        soql += ' WITH SYSTEM_MODE ORDER BY IsActive DESC, Name ASC LIMIT 200';

        List<UserOption> options = new List<UserOption>();
        for (User userRecord : Database.query(soql)) {
            options.add(toUserOption(userRecord));
        }
        return options;
    }

    @AuraEnabled
    public static void updateUserProfile(UserProfileForm form) {
        if (form == null || form.userId == null) {
            throw new AuraHandledException('User is required.');
        }
        if (String.isBlank(form.lastName)) {
            throw new AuraHandledException('Last name is required.');
        }
        if (String.isBlank(form.email)) {
            throw new AuraHandledException('Email is required.');
        }
        if (String.isBlank(form.username)) {
            throw new AuraHandledException('Username is required.');
        }

        User target = [
            SELECT Id, FirstName, LastName, Email, Username, Title, Department, Profile.Name
            FROM User
            WHERE Id = :form.userId
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        target.FirstName = String.isBlank(form.firstName) ? null : form.firstName.trim();
        target.LastName = form.lastName.trim();
        target.Email = form.email.trim();
        target.Username = form.username.trim();
        target.Title = String.isBlank(form.title) ? null : form.title.trim();
        target.Department = String.isBlank(form.department) ? null : form.department.trim();

        try {
            update as system target;
        } catch (DmlException ex) {
            throw new AuraHandledException(ex.getDmlMessage(0));
        }
    }

    @AuraEnabled
    public static PasswordSetResult setOneTimePasswords(List<Id> userIds, String password) {
        if (userIds == null || userIds.isEmpty()) {
            throw new AuraHandledException('Select at least one user.');
        }

        String resolvedPassword = String.isBlank(password) ? generateOneTimePassword() : password.trim();
        if (resolvedPassword.length() < 8) {
            throw new AuraHandledException('Password must be at least 8 characters.');
        }

        PasswordSetResult result = new PasswordSetResult();
        result.successCount = 0;
        result.failureCount = 0;
        result.passwordUsed = resolvedPassword;
        result.messages = new List<String>();

        Set<Id> uniqueIds = new Set<Id>(userIds);
        Map<Id, User> usersById = new Map<Id, User>([
            SELECT Id, Name, Username, IsActive
            FROM User
            WHERE Id IN :uniqueIds
            WITH SYSTEM_MODE
        ]);

        for (Id userId : uniqueIds) {
            User target = usersById.get(userId);
            if (target == null) {
                result.failureCount++;
                result.messages.add('User not found: ' + String.valueOf(userId));
                continue;
            }
            if (!target.IsActive) {
                result.failureCount++;
                result.messages.add(target.Name + ': inactive users cannot receive a password reset here.');
                continue;
            }
            try {
                System.setPassword(userId, resolvedPassword);
                result.successCount++;
                result.messages.add(target.Name + ': one-time password set.');
            } catch (Exception ex) {
                result.failureCount++;
                result.messages.add(target.Name + ': ' + ex.getMessage());
            }
        }
        return result;
    }

    @AuraEnabled
    public static UserStatusResult setUsersActive(List<Id> userIds, Boolean isActive) {
        if (userIds == null || userIds.isEmpty()) {
            throw new AuraHandledException('Select at least one user.');
        }
        if (isActive == null) {
            throw new AuraHandledException('Active flag is required.');
        }

        UserStatusResult result = new UserStatusResult();
        result.successCount = 0;
        result.skippedCount = 0;
        result.failureCount = 0;
        result.messages = new List<String>();

        Set<Id> uniqueIds = new Set<Id>(userIds);
        List<User> targets = [
            SELECT Id, Name, IsActive, Profile.Name
            FROM User
            WHERE Id IN :uniqueIds
            WITH SYSTEM_MODE
        ];

        List<User> toUpdate = new List<User>();
        for (User target : targets) {
            if (!isActive && isSystemAdministrator(target.Profile?.Name)) {
                result.skippedCount++;
                result.messages.add(target.Name + ': System Administrators cannot be deactivated here.');
                continue;
            }
            if (!isActive && target.Id == UserInfo.getUserId()) {
                result.skippedCount++;
                result.messages.add(target.Name + ': you cannot deactivate your own user.');
                continue;
            }
            if (target.IsActive == isActive) {
                result.skippedCount++;
                result.messages.add(
                    target.Name + ': already ' + (isActive ? 'active' : 'inactive') + '.'
                );
                continue;
            }
            target.IsActive = isActive;
            toUpdate.add(target);
        }

        if (!toUpdate.isEmpty()) {
            Database.SaveResult[] saveResults = Database.update(toUpdate, false, AccessLevel.SYSTEM_MODE);
            for (Integer i = 0; i < saveResults.size(); i++) {
                Database.SaveResult saveResult = saveResults[i];
                User target = toUpdate[i];
                if (saveResult.isSuccess()) {
                    result.successCount++;
                    result.messages.add(
                        target.Name + ': ' + (isActive ? 'activated' : 'deactivated') + '.'
                    );
                } else {
                    result.failureCount++;
                    result.messages.add(target.Name + ': ' + saveResult.getErrors()[0].getMessage());
                }
            }
        }
        return result;
    }

    private static UserOption toUserOption(User userRecord) {
        UserOption option = new UserOption();
        option.id = userRecord.Id;
        option.name = userRecord.Name;
        option.firstName = userRecord.FirstName;
        option.lastName = userRecord.LastName;
        option.email = userRecord.Email;
        option.username = userRecord.Username;
        option.title = resolveTitle(userRecord);
        option.businessUnit = resolveBusinessUnit(userRecord);
        option.profileName = userRecord.Profile != null ? userRecord.Profile.Name : null;
        option.isActive = userRecord.IsActive;
        option.isSystemAdmin = isSystemAdministrator(option.profileName);
        option.canDeactivate = userRecord.IsActive == true
            && option.isSystemAdmin != true
            && userRecord.Id != UserInfo.getUserId();
        option.label = buildUserDisplayLabel(userRecord, option.title, option.businessUnit);
        return option;
    }

    private static Boolean isSystemAdministrator(String profileName) {
        return String.isNotBlank(profileName) && profileName == 'System Administrator';
    }

    private static String generateOneTimePassword() {
        String alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
        String randomPart = '';
        while (randomPart.length() < 10) {
            Integer idx = Math.mod(Math.abs(Crypto.getRandomInteger()), alphabet.length());
            randomPart += alphabet.substring(idx, idx + 1);
        }
        return 'Zeta!' + randomPart;
    }

    private static String resolveTitle(User userRecord) {
        if (String.isNotBlank(userRecord.Title)) {
            return userRecord.Title;
        }
        String username = userRecord.Username == null ? '' : userRecord.Username.toLowerCase();
        if (!username.endsWith('@pharma.demo')) {
            return null;
        }
        String localPart = username.substringBefore('@');
        if (localPart.endsWith('.dm')) {
            return 'District Manager';
        }
        if (localPart.endsWith('.mr')) {
            return 'Medical Rep';
        }
        return null;
    }

    private static String resolveBusinessUnit(User userRecord) {
        if (String.isNotBlank(userRecord.Department)) {
            return userRecord.Department;
        }
        if (String.isNotBlank(userRecord.Division)) {
            return userRecord.Division;
        }
        String username = userRecord.Username == null ? '' : userRecord.Username.toLowerCase();
        if (!username.endsWith('@pharma.demo')) {
            return null;
        }
        String localPart = username.substringBefore('@');
        if (!localPart.contains('.')) {
            return null;
        }
        return localPart.substringBefore('.').toUpperCase();
    }

    private static String buildUserDisplayLabel(User userRecord, String title, String businessUnit) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(userRecord.Name)) {
            parts.add(userRecord.Name);
        }
        if (String.isNotBlank(title)) {
            parts.add(title);
        }
        if (String.isNotBlank(businessUnit)) {
            parts.add(businessUnit);
        }
        if (String.isNotBlank(userRecord.Username)) {
            parts.add(userRecord.Username);
        }
        return String.join(parts, ' · ');
    }

    @AuraEnabled(cacheable=true)
    public static String resolveAssignmentRole(Id userId) {
        if (userId == null) {
            return 'Medical Rep';
        }
        List<User> users = [
            SELECT Username, Title
            FROM User
            WHERE Id = :userId
            WITH USER_MODE
            LIMIT 1
        ];
        if (users.isEmpty()) {
            return 'Medical Rep';
        }
        User userRecord = users[0];
        if (String.isNotBlank(userRecord.Title)) {
            if (userRecord.Title == 'District Manager') {
                return 'District Manager';
            }
            if (userRecord.Title == 'Medical Rep') {
                return 'Medical Rep';
            }
            if (userRecord.Title == 'Sales Force Excellence' || userRecord.Title == 'SFE') {
                return 'SFE';
            }
        }
        String username = userRecord.Username == null ? '' : userRecord.Username.toLowerCase();
        if (username == 'admin@pharma.eg') {
            return 'SFE';
        }
        if (username.endsWith('.dm@pharma.demo')) {
            return 'District Manager';
        }
        if (username.endsWith('.mr@pharma.demo')) {
            return 'Medical Rep';
        }
        return 'Medical Rep';
    }

    @AuraEnabled
    public static void assignUserToTerritory(Id territoryId, Id userId, String role) {
        if (territoryId == null || userId == null) {
            throw new AuraHandledException('Territory and user are required.');
        }

        Boolean isLeaf = isLeafTerritory(territoryId);
        if (isLeaf) {
            delete as user [
                SELECT Id
                FROM UserTerritory2Association
                WHERE Territory2Id = :territoryId
                WITH USER_MODE
            ];
        }

        insert as user new UserTerritory2Association(
            UserId = userId,
            Territory2Id = territoryId,
            RoleInTerritory2 = String.isBlank(role) ? 'Medical Rep' : role
        );
    }

    @AuraEnabled
    public static void clearTerritoryAssignments(Id territoryId) {
        if (territoryId == null) {
            throw new AuraHandledException('Territory Id is required.');
        }
        delete as user [
            SELECT Id
            FROM UserTerritory2Association
            WHERE Territory2Id = :territoryId
            WITH USER_MODE
        ];
    }

    private static Map<Id, List<TerritoryAssignment>> loadAssignments(Set<Id> territoryIds) {
        Map<Id, List<TerritoryAssignment>> assignmentsByTerritory = new Map<Id, List<TerritoryAssignment>>();
        for (UserTerritory2Association association : [
            SELECT Id, Territory2Id, UserId, RoleInTerritory2, User.Name
            FROM UserTerritory2Association
            WHERE Territory2Id IN :territoryIds
            WITH SYSTEM_MODE
            ORDER BY User.Name ASC
        ]) {
            if (!assignmentsByTerritory.containsKey(association.Territory2Id)) {
                assignmentsByTerritory.put(association.Territory2Id, new List<TerritoryAssignment>());
            }
            TerritoryAssignment assignment = new TerritoryAssignment();
            assignment.associationId = association.Id;
            assignment.userId = association.UserId;
            assignment.userName = association.User?.Name;
            assignment.role = association.RoleInTerritory2;
            assignmentsByTerritory.get(association.Territory2Id).add(assignment);
        }
        return assignmentsByTerritory;
    }

    private static TerritoryTreeNode buildNode(Territory2 territory, List<TerritoryAssignment> assignments) {
        TerritoryTreeNode node = new TerritoryTreeNode();
        node.id = territory.Id;
        node.name = territory.Name;
        node.externalId = territory.External_ID__c;
        String territoryType = null;
        if (Schema.SObjectType.Territory2.fields.getMap().containsKey('Territory_Type__c')) {
            territoryType = (String) territory.get('Territory_Type__c');
        }
        node.level = resolveNodeLevel(territory.External_ID__c, territoryType);
        node.parentId = territory.ParentTerritory2Id;
        node.assignments = assignments == null ? new List<TerritoryAssignment>() : assignments;
        node.isVacant = node.assignments.isEmpty();
        node.children = new List<TerritoryTreeNode>();
        node.hasChildren = false;
        node.canEdit = territory.External_ID__c != 'TERR_HEAD_OFFICE';
        node.canDelete = node.canEdit;
        node.canAddChild = node.level != 'MR' && node.level != 'Position';
        return node;
    }

    private static String resolveNodeLevel(String externalId, String territoryType) {
        if (String.isNotBlank(territoryType)) {
            if (territoryType == 'Head_Office') {
                return 'Head Office';
            }
            if (territoryType == 'Business_Unit') {
                return 'Business Unit';
            }
            if (territoryType == 'Line') {
                return 'Line';
            }
            if (territoryType == 'District') {
                return 'District';
            }
            if (territoryType == 'Position') {
                return 'Position';
            }
        }
        if (String.isBlank(externalId)) {
            return 'Unknown';
        }
        if (externalId == 'TERR_HEAD_OFFICE') {
            return 'Head Office';
        }
        if (externalId.startsWith('TERR_BU_')) {
            return 'Business Unit';
        }
        if (externalId.startsWith('TERR_POS_') || externalId.contains('_MR_')) {
            return externalId.contains('_MR_') ? 'MR' : 'Position';
        }
        if (externalId.startsWith('TERR_DM_') || externalId.contains('_DM_')) {
            return 'District';
        }
        if (externalId.startsWith('TERR_LINE_')) {
            return 'Line';
        }
        return 'Line';
    }

    private static Boolean isLeafTerritory(Id territoryId) {
        Integer childCount = [
            SELECT COUNT()
            FROM Territory2
            WHERE ParentTerritory2Id = :territoryId
            WITH USER_MODE
        ];
        return childCount == 0;
    }

    private static void sortChildrenRecursively(List<TerritoryTreeNode> nodes) {
        if (nodes == null) {
            return;
        }
        nodes.sort(new TerritoryNodeNameComparator());
        for (TerritoryTreeNode node : nodes) {
            if (node.children != null && !node.children.isEmpty()) {
                sortChildrenRecursively(node.children);
            }
        }
    }

    private class TerritoryNodeNameComparator implements Comparator<TerritoryTreeNode> {
        public Integer compare(TerritoryTreeNode a, TerritoryTreeNode b) {
            String left = a != null && a.name != null ? a.name : '';
            String right = b != null && b.name != null ? b.name : '';
            return left.compareTo(right);
        }
    }
}