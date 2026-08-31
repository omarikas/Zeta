public with sharing class ProductCatalogAdminController {

    public class ProductTreeNode {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public String nodeType;
        @AuraEnabled public Id productId;
        @AuraEnabled public String therapyArea;
        @AuraEnabled public String productCode;
        @AuraEnabled public String imageUrl;
        @AuraEnabled public List<ProductTreeNode> children;
    }

    public class TerritoryTreeNode {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Id parentId;
        @AuraEnabled public Boolean hasChildren;
        @AuraEnabled public Boolean aligned;
        @AuraEnabled public List<TerritoryTreeNode> children;
    }

    @AuraEnabled(cacheable=true)
    public static List<ProductTreeNode> getProductCatalogTree() {
        Map<String, List<Product2>> productsByFamily = new Map<String, List<Product2>>();
        for (Product2 product : [
            SELECT Id, Name, Family, Primary_Brand__c, Therapy_Area__c, ProductCode, External_ID__c, Product_Image_URL__c
            FROM Product2
            WHERE IsActive = TRUE
            WITH USER_MODE
            ORDER BY Family ASC, Name ASC
        ]) {
            String family = String.isNotBlank(product.Family)
                ? product.Family
                : (String.isNotBlank(product.Primary_Brand__c) ? product.Primary_Brand__c : 'Unassigned');
            if (!productsByFamily.containsKey(family)) {
                productsByFamily.put(family, new List<Product2>());
            }
            productsByFamily.get(family).add(product);
        }

        List<String> familyNames = new List<String>(productsByFamily.keySet());
        familyNames.sort();

        List<ProductTreeNode> roots = new List<ProductTreeNode>();
        for (String family : familyNames) {
            ProductTreeNode familyNode = new ProductTreeNode();
            familyNode.key = 'family:' + family;
            familyNode.label = family;
            familyNode.nodeType = 'family';
            familyNode.children = new List<ProductTreeNode>();

            for (Product2 product : productsByFamily.get(family)) {
                ProductTreeNode productNode = new ProductTreeNode();
                productNode.key = String.valueOf(product.Id);
                productNode.label = product.Name;
                productNode.nodeType = 'product';
                productNode.productId = product.Id;
                productNode.therapyArea = product.Therapy_Area__c;
                productNode.productCode = product.ProductCode;
                productNode.imageUrl = product.Product_Image_URL__c;
                productNode.children = new List<ProductTreeNode>();
                familyNode.children.add(productNode);
            }
            roots.add(familyNode);
        }
        return roots;
    }

    @AuraEnabled(cacheable=true)
    public static List<TerritoryTreeNode> getTerritoryTreeForProduct(Id productId) {
        Set<String> alignedTerritoryIds = loadAlignedTerritoryIds(productId);
        return buildTerritoryTree(alignedTerritoryIds);
    }

    @AuraEnabled
    public static Integer saveProductTerritoryAlignments(Id productId, List<Id> territoryIds) {
        if (productId == null) {
            throw new AuraHandledException('Select a product before saving territory alignment.');
        }

        Set<Id> requestedTerritoryIds = territoryIds == null
            ? new Set<Id>()
            : new Set<Id>(territoryIds);

        List<Product_Territory_Alignment__c> existing = [
            SELECT Id, Territory2_Id__c
            FROM Product_Territory_Alignment__c
            WHERE Product2_Id__c = :String.valueOf(productId)
            WITH USER_MODE
        ];

        List<Product_Territory_Alignment__c> toDelete = new List<Product_Territory_Alignment__c>();
        Set<Id> existingTerritoryIds = new Set<Id>();
        for (Product_Territory_Alignment__c alignment : existing) {
            Id territoryId = parseTerritoryId(alignment.Territory2_Id__c);
            if (territoryId == null) {
                toDelete.add(alignment);
                continue;
            }
            existingTerritoryIds.add(territoryId);
            if (!requestedTerritoryIds.contains(territoryId)) {
                toDelete.add(alignment);
            }
        }
        if (!toDelete.isEmpty()) {
            delete as user toDelete;
        }

        List<Product_Territory_Alignment__c> toInsert = new List<Product_Territory_Alignment__c>();
        for (Id territoryId : requestedTerritoryIds) {
            if (territoryId == null || existingTerritoryIds.contains(territoryId)) {
                continue;
            }
            toInsert.add(new Product_Territory_Alignment__c(
                Product2_Id__c = String.valueOf(productId),
                Territory2_Id__c = String.valueOf(territoryId),
                Is_Active__c = true,
                Effective_Start_Date__c = Date.today()
            ));
        }
        if (!toInsert.isEmpty()) {
            insert as user toInsert;
        }
        return requestedTerritoryIds.size();
    }

    private static Set<String> loadAlignedTerritoryIds(Id productId) {
        Set<String> aligned = new Set<String>();
        if (productId == null) {
            return aligned;
        }
        for (Product_Territory_Alignment__c alignment : [
            SELECT Territory2_Id__c
            FROM Product_Territory_Alignment__c
            WHERE Product2_Id__c = :String.valueOf(productId)
                AND Is_Active__c = TRUE
            WITH USER_MODE
        ]) {
            if (alignment.Territory2_Id__c != null) {
                aligned.add(alignment.Territory2_Id__c);
            }
        }
        return aligned;
    }

    private static List<TerritoryTreeNode> buildTerritoryTree(Set<String> alignedTerritoryIds) {
        List<Territory2> territories = [
            SELECT Id, Name, ParentTerritory2Id
            FROM Territory2
            WHERE External_ID__c LIKE 'TERR_%'
            WITH USER_MODE
            ORDER BY Name ASC
            LIMIT 500
        ];
        if (territories.isEmpty()) {
            return new List<TerritoryTreeNode>();
        }

        Map<Id, List<TerritoryTreeNode>> childrenByParent = new Map<Id, List<TerritoryTreeNode>>();
        Map<Id, TerritoryTreeNode> nodesById = new Map<Id, TerritoryTreeNode>();

        for (Territory2 territory : territories) {
            TerritoryTreeNode node = new TerritoryTreeNode();
            node.id = territory.Id;
            node.name = territory.Name;
            node.parentId = territory.ParentTerritory2Id;
            node.aligned = alignedTerritoryIds.contains(String.valueOf(territory.Id));
            node.children = new List<TerritoryTreeNode>();
            node.hasChildren = false;
            nodesById.put(territory.Id, node);
        }

        for (Territory2 territory : territories) {
            TerritoryTreeNode node = nodesById.get(territory.Id);
            if (territory.ParentTerritory2Id != null && nodesById.containsKey(territory.ParentTerritory2Id)) {
                if (!childrenByParent.containsKey(territory.ParentTerritory2Id)) {
                    childrenByParent.put(territory.ParentTerritory2Id, new List<TerritoryTreeNode>());
                }
                childrenByParent.get(territory.ParentTerritory2Id).add(node);
            }
        }

        for (Id parentId : childrenByParent.keySet()) {
            if (nodesById.containsKey(parentId)) {
                List<TerritoryTreeNode> children = childrenByParent.get(parentId);
                children.sort(new TerritoryNodeNameComparator());
                nodesById.get(parentId).children = children;
                nodesById.get(parentId).hasChildren = !children.isEmpty();
            }
        }

        List<TerritoryTreeNode> roots = new List<TerritoryTreeNode>();
        for (Territory2 territory : territories) {
            TerritoryTreeNode node = nodesById.get(territory.Id);
            if (territory.ParentTerritory2Id == null || !nodesById.containsKey(territory.ParentTerritory2Id)) {
                roots.add(node);
            }
        }
        roots.sort(new TerritoryNodeNameComparator());
        return roots;
    }

    private static Id parseTerritoryId(String territoryIdValue) {
        if (String.isBlank(territoryIdValue)) {
            return null;
        }
        try {
            return (Id) territoryIdValue;
        } catch (Exception ex) {
            return null;
        }
    }

    private class TerritoryNodeNameComparator implements Comparator<TerritoryTreeNode> {
        public Integer compare(TerritoryTreeNode left, TerritoryTreeNode right) {
            String leftName = left != null && left.name != null ? left.name : '';
            String rightName = right != null && right.name != null ? right.name : '';
            return leftName.compareTo(rightName);
        }
    }
}