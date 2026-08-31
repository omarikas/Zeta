public without sharing class TerritoryHierarchyService {

    private static final String HEAD_OFFICE_EXTERNAL_ID = 'TERR_HEAD_OFFICE';
    private static final String ROLE_MEDICAL_REP = 'Medical Rep';
    private static final String ROLE_DISTRICT_MANAGER = 'District Manager';
    private static final String ROLE_REGION_MANAGER = 'Region Manager';

    public class HierarchyLabels {
        @AuraEnabled public String businessUnit;
        @AuraEnabled public String line;
        @AuraEnabled public String district;
        @AuraEnabled public Id lineTerritoryId;
        @AuraEnabled public Id districtTerritoryId;
        @AuraEnabled public Id buTerritoryId;
    }

    public class TerritoryNode {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String level;
        @AuraEnabled public Id parentId;
    }

    public class FilterOption {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
        @AuraEnabled public Id territoryId;
    }

    public class DrillDownRow {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public String level;
        @AuraEnabled public Id territoryId;
        @AuraEnabled public Id employeeId;
        @AuraEnabled public Decimal coveragePercent;
        @AuraEnabled public Decimal actualVisitRate;
        @AuraEnabled public Decimal kolCoveragePercent;
        @AuraEnabled public Decimal coachingDays;
        @AuraEnabled public Integer singleVisits;
        @AuraEnabled public Integer doubleVisits;
        @AuraEnabled public List<DrillDownRow> children;
    }

    public static Map<Id, HierarchyLabels> resolveHierarchyLabelsForEmployees(Set<Id> employeeIds) {
        Map<Id, HierarchyLabels> result = new Map<Id, HierarchyLabels>();
        if (employeeIds == null || employeeIds.isEmpty()) {
            return result;
        }

        Map<Id, Id> primaryTerritoryByUser = resolvePrimaryTerritoryByUser(employeeIds);
        Set<Id> territoryIds = new Set<Id>(primaryTerritoryByUser.values());
        Map<Id, Territory2> territoryById = loadTerritoriesWithAncestors(territoryIds);

        for (Id employeeId : employeeIds) {
            Id territoryId = primaryTerritoryByUser.get(employeeId);
            if (territoryId == null) {
                continue;
            }
            result.put(employeeId, buildLabelsFromTerritory(territoryId, territoryById));
        }
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<FilterOption> getBusinessUnitOptions() {
        Id headOfficeId = getHeadOfficeTerritoryId();
        if (headOfficeId == null) {
            return new List<FilterOption>();
        }
        List<FilterOption> options = new List<FilterOption>();
        options.add(buildFilterOption('ALL', 'All Business Units', headOfficeId));
        for (Territory2 line : [
            SELECT Id, Name
            FROM Territory2
            WHERE ParentTerritory2Id = :headOfficeId
            WITH SYSTEM_MODE
            ORDER BY Name ASC
        ]) {
            options.add(buildFilterOption(line.Id, line.Name, line.Id));
        }
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<FilterOption> getLineOptions(Id businessUnitTerritoryId) {
        Id headOfficeId = getHeadOfficeTerritoryId();
        Id parentId = businessUnitTerritoryId == null || String.valueOf(businessUnitTerritoryId) == 'ALL'
            ? headOfficeId
            : businessUnitTerritoryId;
        if (parentId == null) {
            return new List<FilterOption>();
        }
        List<FilterOption> options = new List<FilterOption>();
        options.add(buildFilterOption('ALL', 'All Lines', parentId));
        for (Territory2 line : [
            SELECT Id, Name
            FROM Territory2
            WHERE ParentTerritory2Id = :parentId
            WITH SYSTEM_MODE
            ORDER BY Name ASC
            LIMIT 6
        ]) {
            options.add(buildFilterOption(line.Id, line.Name, line.Id));
        }
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<FilterOption> getDistrictOptions(Id lineTerritoryId) {
        if (lineTerritoryId == null || String.valueOf(lineTerritoryId) == 'ALL') {
            return new List<FilterOption>{ buildFilterOption('ALL', 'All Districts', null) };
        }
        List<FilterOption> options = new List<FilterOption>();
        options.add(buildFilterOption('ALL', 'All Districts', lineTerritoryId));
        for (Territory2 district : [
            SELECT Id, Name
            FROM Territory2
            WHERE ParentTerritory2Id = :lineTerritoryId
            WITH SYSTEM_MODE
            ORDER BY Name ASC
        ]) {
            options.add(buildFilterOption(district.Id, district.Name, district.Id));
        }
        return options;
    }

    public static Set<Id> resolveScopedEmployeeIds(Id buTerritoryId, Id lineTerritoryId, Id districtTerritoryId) {
        Set<Id> territoryIds = resolveScopedTerritoryIds(buTerritoryId, lineTerritoryId, districtTerritoryId);
        Set<Id> employeeIds = new Set<Id>();
        if (territoryIds.isEmpty()) {
            return employeeIds;
        }
        for (UserTerritory2Association uta : [
            SELECT UserId, RoleInTerritory2
            FROM UserTerritory2Association
            WHERE Territory2Id IN :territoryIds
            AND RoleInTerritory2 = :ROLE_MEDICAL_REP
            WITH SYSTEM_MODE
        ]) {
            employeeIds.add(uta.UserId);
        }
        return employeeIds;
    }

    public static Integer countScopedManagers(Id buTerritoryId, Id lineTerritoryId, Id districtTerritoryId) {
        return resolveScopedManagerIds(buTerritoryId, lineTerritoryId, districtTerritoryId).size();
    }

    public static Set<Id> resolveScopedManagerIds(Id buTerritoryId, Id lineTerritoryId, Id districtTerritoryId) {
        Set<Id> territoryIds = resolveScopedTerritoryIds(buTerritoryId, lineTerritoryId, districtTerritoryId);
        Set<Id> managerIds = new Set<Id>();
        if (territoryIds.isEmpty()) {
            return managerIds;
        }
        for (UserTerritory2Association uta : [
            SELECT UserId
            FROM UserTerritory2Association
            WHERE
                Territory2Id IN :territoryIds
                AND RoleInTerritory2 IN (:ROLE_DISTRICT_MANAGER, :ROLE_REGION_MANAGER)
            WITH SYSTEM_MODE
        ]) {
            managerIds.add(uta.UserId);
        }
        return managerIds;
    }

    public static Map<Id, String> resolvePrimaryRoleByUser(Set<Id> userIds) {
        Map<Id, String> result = new Map<Id, String>();
        if (userIds == null || userIds.isEmpty()) {
            return result;
        }
        for (UserTerritory2Association uta : [
            SELECT UserId, RoleInTerritory2
            FROM UserTerritory2Association
            WHERE UserId IN :userIds
            WITH SYSTEM_MODE
            ORDER BY RoleInTerritory2 ASC, Territory2Id ASC
        ]) {
            if (!result.containsKey(uta.UserId)) {
                result.put(uta.UserId, uta.RoleInTerritory2);
            }
        }
        return result;
    }

    public static Set<Id> resolveScopedTerritoryIds(Id buTerritoryId, Id lineTerritoryId, Id districtTerritoryId) {
        Id headOfficeId = getHeadOfficeTerritoryId();
        Id rootId = headOfficeId;

        if (districtTerritoryId != null && String.valueOf(districtTerritoryId) != 'ALL') {
            rootId = districtTerritoryId;
        } else if (lineTerritoryId != null && String.valueOf(lineTerritoryId) != 'ALL') {
            rootId = lineTerritoryId;
        } else if (buTerritoryId != null && String.valueOf(buTerritoryId) != 'ALL') {
            rootId = buTerritoryId;
        }

        if (rootId == null) {
            return new Set<Id>();
        }
        return expandTerritoryHierarchy(new Set<Id>{ rootId });
    }

    public static Set<Id> expandTerritoryHierarchy(Set<Id> rootTerritoryIds) {
        Set<Id> expanded = new Set<Id>(rootTerritoryIds);
        List<Id> frontier = new List<Id>(rootTerritoryIds);
        while (!frontier.isEmpty()) {
            List<Id> nextFrontier = new List<Id>();
            for (Territory2 child : [
                SELECT Id
                FROM Territory2
                WHERE ParentTerritory2Id IN :frontier
                WITH SYSTEM_MODE
            ]) {
                if (!expanded.contains(child.Id)) {
                    expanded.add(child.Id);
                    nextFrontier.add(child.Id);
                }
            }
            frontier = nextFrontier;
        }
        return expanded;
    }

    private static HierarchyLabels buildLabelsFromTerritory(Id territoryId, Map<Id, Territory2> territoryById) {
        HierarchyLabels labels = new HierarchyLabels();
        List<Territory2> chain = new List<Territory2>();
        Id currentId = territoryId;
        Integer guard = 0;
        while (currentId != null && guard < 10) {
            Territory2 node = territoryById.get(currentId);
            if (node == null) {
                break;
            }
            chain.add(node);
            currentId = node.ParentTerritory2Id;
            guard++;
        }

        if (chain.isEmpty()) {
            return labels;
        }

        Id headOfficeId = getHeadOfficeTerritoryId();
        Integer depth = chain.size();
        Integer buIndex = depth - 1;
        if (headOfficeId != null && chain[buIndex].Id == headOfficeId && buIndex > 0) {
            buIndex--;
        }

        labels.businessUnit = chain[buIndex].Name;
        labels.buTerritoryId = chain[buIndex].Id;

        if (buIndex >= 1) {
            labels.line = chain[buIndex - 1].Name;
            labels.lineTerritoryId = chain[buIndex - 1].Id;
        }
        if (buIndex >= 2) {
            labels.district = chain[buIndex - 2].Name;
            labels.districtTerritoryId = chain[buIndex - 2].Id;
        }
        return labels;
    }

    private static Map<Id, Id> resolvePrimaryTerritoryByUser(Set<Id> userIds) {
        Map<Id, Id> result = new Map<Id, Id>();
        for (UserTerritory2Association uta : [
            SELECT UserId, Territory2Id, RoleInTerritory2
            FROM UserTerritory2Association
            WHERE UserId IN :userIds
            WITH SYSTEM_MODE
            ORDER BY RoleInTerritory2 ASC, Territory2Id ASC
        ]) {
            if (!result.containsKey(uta.UserId)) {
                result.put(uta.UserId, uta.Territory2Id);
            }
        }
        return result;
    }

    private static Map<Id, Territory2> loadTerritoriesWithAncestors(Set<Id> territoryIds) {
        Map<Id, Territory2> result = new Map<Id, Territory2>();
        Set<Id> toLoad = new Set<Id>(territoryIds);
        Integer guard = 0;
        while (!toLoad.isEmpty() && guard < 10) {
            Set<Id> parentIds = new Set<Id>();
            for (Territory2 t : [
                SELECT Id, Name, ParentTerritory2Id
                FROM Territory2
                WHERE Id IN :toLoad
                WITH SYSTEM_MODE
            ]) {
                result.put(t.Id, t);
                if (t.ParentTerritory2Id != null && !result.containsKey(t.ParentTerritory2Id)) {
                    parentIds.add(t.ParentTerritory2Id);
                }
            }
            toLoad = parentIds;
            guard++;
        }
        return result;
    }

    private static Id getHeadOfficeTerritoryId() {
        List<Territory2> territories = [
            SELECT Id
            FROM Territory2
            WHERE External_ID__c = :HEAD_OFFICE_EXTERNAL_ID
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return territories.isEmpty() ? null : territories[0].Id;
    }

    private static FilterOption buildFilterOption(Object value, String label, Id territoryId) {
        FilterOption opt = new FilterOption();
        opt.value = String.valueOf(value);
        opt.label = label;
        opt.territoryId = territoryId;
        return opt;
    }

    // Compatibility shims used by existing Zeta tests / callers.
    public class Node {
        public Id id;
        public String name;
        public Id parentId;
    }

    public static List<Node> getHierarchy() {
        return new List<Node>();
    }

    public static Set<Id> getAccessibleTerritoryIds() {
        return getUserTerritoryId(UserInfo.getUserId()) == null
            ? new Set<Id>()
            : expandTerritoryHierarchy(new Set<Id>{ getUserTerritoryId(UserInfo.getUserId()) });
    }

    public static Id getUserTerritoryId(Id userId) {
        if (userId == null) {
            return null;
        }
        Map<Id, Id> byUser = resolvePrimaryTerritoryByUser(new Set<Id>{ userId });
        return byUser.get(userId);
    }

    public static Map<Id, String> getTerritoryNames(Set<Id> ids) {
        Map<Id, String> names = new Map<Id, String>();
        if (ids == null || ids.isEmpty()) {
            return names;
        }
        for (Territory2 territory : [
            SELECT Id, Name
            FROM Territory2
            WHERE Id IN :ids
            WITH SYSTEM_MODE
        ]) {
            names.put(territory.Id, territory.Name);
        }
        return names;
    }
}
