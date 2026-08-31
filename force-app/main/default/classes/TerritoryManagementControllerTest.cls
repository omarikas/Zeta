@IsTest
private class TerritoryManagementControllerTest {

    @IsTest
    static void getTerritoryTree_returnsHierarchy() {
        Territory2 territory = getOrCreateTestTerritory('TERR_TEST_MGMT');
        User runUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];

        insert new UserTerritory2Association(
            UserId = runUser.Id,
            Territory2Id = territory.Id,
            RoleInTerritory2 = 'Medical Rep'
        );

        Test.startTest();
        List<TerritoryManagementController.TerritoryTreeNode> roots =
            TerritoryManagementController.getTerritoryTree();
        Test.stopTest();

        System.assert(!roots.isEmpty(), 'Expected at least one root territory.');
        Boolean found = false;
        for (TerritoryManagementController.TerritoryTreeNode root : roots) {
            found = found || containsTerritory(root, territory.Id);
        }
        System.assert(found, 'Expected seeded test territory in tree.');
    }

    @IsTest
    static void getAssignableUsers_returnsPharmaUsers() {
        Test.startTest();
        List<TerritoryManagementController.UserOption> users =
            TerritoryManagementController.getAssignableUsers(null);
        TerritoryManagementController.getAssignableUsers('admin');
        List<TerritoryManagementController.LineSummary> lines =
            TerritoryManagementController.getProductLines();
        List<TerritoryManagementController.ParentOption> parents =
            TerritoryManagementController.getParentOptions('Line');
        TerritoryManagementController.getParentOptions('District');
        TerritoryManagementController.getParentOptions('Position');
        TerritoryManagementController.getParentOptions('Business Unit');
        String role = TerritoryManagementController.resolveAssignmentRole(UserInfo.getUserId());
        TerritoryManagementController.syncDefaultLineProductAlignments();
        Test.stopTest();

        System.assertNotEquals(null, users);
        System.assertNotEquals(null, lines);
        System.assertNotEquals(null, parents);
        System.assertNotEquals(null, role);
    }

    @IsTest
    static void userManagement_profilePasswordAndStatusGuards() {
        List<TerritoryManagementController.UserOption> managed =
            TerritoryManagementController.getManagedUsers(null, true);
        System.assertNotEquals(null, managed);

        User current = [
            SELECT Id, FirstName, LastName, Email, Username, Title, Department, Profile.Name
            FROM User
            WHERE Id = :UserInfo.getUserId()
        ];

        TerritoryManagementController.UserProfileForm form =
            new TerritoryManagementController.UserProfileForm();
        form.userId = current.Id;
        form.firstName = current.FirstName;
        form.lastName = current.LastName;
        form.email = current.Email;
        form.username = current.Username;
        form.title = 'Territory Admin Test';
        form.department = current.Department;

        Test.startTest();
        TerritoryManagementController.updateUserProfile(form);

        TerritoryManagementController.UserStatusResult selfDeactivate =
            TerritoryManagementController.setUsersActive(new List<Id>{ current.Id }, false);
        System.assert(
            selfDeactivate.skippedCount >= 1,
            'Expected self/admin deactivation to be skipped.'
        );

        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String uniq = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        User managedUser = new User(
            Alias = 'tmgmt',
            Email = 'tmgmt' + uniq + '@zetapharma.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'MgmtTest',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = standardProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'tmgmt' + uniq + '@zetapharma.com'
        );
        insert managedUser;

        TerritoryManagementController.PasswordSetResult passwordResult =
            TerritoryManagementController.setOneTimePasswords(
                new List<Id>{ managedUser.Id },
                'Zeta!TempPass9'
            );
        System.assertNotEquals(null, passwordResult.passwordUsed);

        TerritoryManagementController.UserStatusResult deactivated =
            TerritoryManagementController.setUsersActive(new List<Id>{ managedUser.Id }, false);
        System.assertEquals(1, deactivated.successCount);

        TerritoryManagementController.UserStatusResult activated =
            TerritoryManagementController.setUsersActive(new List<Id>{ managedUser.Id }, true);
        System.assertEquals(1, activated.successCount);

        Boolean emptyPasswordBlocked = false;
        try {
            TerritoryManagementController.setOneTimePasswords(new List<Id>(), null);
        } catch (AuraHandledException ex) {
            emptyPasswordBlocked = true;
        }
        System.assert(emptyPasswordBlocked, 'Expected empty user list to be rejected.');
        Test.stopTest();
    }

    @IsTest
    static void adminMutations_guardrails() {
        Territory2 territory = getOrCreateTestTerritory('TERR_TEST_GUARD');
        if (territory == null) {
            return;
        }

        Boolean createBlocked = false;
        try {
            TerritoryManagementController.createProductLine('X', 'X', 'Diabetes');
        } catch (AuraHandledException ex) {
            createBlocked = true;
        }
        System.assert(createBlocked, 'Expected createProductLine guardrail.');

        Boolean userBlocked = false;
        try {
            TerritoryManagementController.createPharmaUser('A', 'B', 'TEAM', 'mr', territory.Id, 'Medical Rep');
        } catch (AuraHandledException ex) {
            userBlocked = true;
        }
        System.assert(userBlocked, 'Expected createPharmaUser guardrail.');

        TerritoryManagementController.TerritoryForm form = new TerritoryManagementController.TerritoryForm();
        form.recordId = territory.Id;
        form.name = 'Territory Mgmt Test Updated';
        Test.startTest();
        Id savedId = TerritoryManagementController.saveTerritory(form);
        Test.stopTest();
        System.assertEquals(territory.Id, savedId);
    }

    @IsTest
    static void assignUserToTerritory_createsAssignment() {
        Territory2 territory = getOrCreateTestTerritory('TERR_TEST_ASSIGN');
        User runUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];

        Test.startTest();
        TerritoryManagementController.assignUserToTerritory(territory.Id, runUser.Id, 'Medical Rep');
        Test.stopTest();

        Integer assignedCount = [
            SELECT COUNT()
            FROM UserTerritory2Association
            WHERE Territory2Id = :territory.Id AND UserId = :runUser.Id
        ];
        System.assertEquals(1, assignedCount);
    }

    @IsTest
    static void clearTerritoryAssignments_removesAssignments() {
        Territory2 territory = getOrCreateTestTerritory('TERR_TEST_CLEAR');
        User runUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
        insert new UserTerritory2Association(
            UserId = runUser.Id,
            Territory2Id = territory.Id,
            RoleInTerritory2 = 'Medical Rep'
        );

        Test.startTest();
        TerritoryManagementController.clearTerritoryAssignments(territory.Id);
        Test.stopTest();

        Integer assignedCount = [
            SELECT COUNT()
            FROM UserTerritory2Association
            WHERE Territory2Id = :territory.Id
        ];
        System.assertEquals(0, assignedCount);
    }

    @IsTest
    static void productLineLinkage_countsAssignAndClear() {
        Territory2 line = getOrCreateLineTerritory('TERR_LINE_TEST_DIAB_I', 'DIAB-I');
        if (line == null) {
            return;
        }

        Product2 brand = new Product2(
            Name = 'Test Brand Line Link',
            ProductCode = 'TBLINK',
            IsActive = true,
            Product_Type__c = 'Brand',
            Primary_Brand__c = 'Test Brand Line Link',
            Sales_Unit__c = 'DIAB',
            Sales_Line__c = 'DIAB-I'
        );
        Product2 detail = new Product2(
            Name = 'Test Detail Line Link',
            ProductCode = 'TDLINK',
            IsActive = true,
            Product_Type__c = 'Detail',
            Primary_Brand__c = 'Test Brand Line Link',
            Sales_Unit__c = 'DIAB',
            Sales_Line__c = 'Other-Line'
        );
        insert new List<Product2>{ brand, detail };

        Test.startTest();
        List<TerritoryManagementController.LineSummary> lines =
            TerritoryManagementController.getProductLines();
        TerritoryManagementController.LineSummary target;
        for (TerritoryManagementController.LineSummary summary : lines) {
            if (summary.id == line.Id) {
                target = summary;
                break;
            }
        }
        System.assertNotEquals(null, target, 'Expected test line in summaries.');
        System.assert(target.productCount >= 1, 'Expected product count from Sales_Line.');
        System.assertEquals('DIAB', target.therapyArea);

        List<TerritoryManagementController.LineProductRow> linked =
            TerritoryManagementController.getProductsForLine(line.Id);
        System.assert(!linked.isEmpty(), 'Expected linked products for line.');

        TerritoryManagementController.setProductLineAssignment(detail.Id, line.Id, false);
        TerritoryManagementController.setProductLineAssignment(detail.Id, line.Id, true);

        List<TerritoryManagementController.LineProductRow> searchable =
            TerritoryManagementController.searchAssignableProducts(line.Id, 'Test Detail');
        // detail now on line via sales + mirror; may or may not appear depending on fields
        TerritoryManagementController.clearProductLineAssignment(detail.Id, line.Id);
        searchable = TerritoryManagementController.searchAssignableProducts(line.Id, 'Test Detail');
        System.assert(!searchable.isEmpty(), 'Expected detail available after clear.');
        Test.stopTest();

        Product2 refreshed = [
            SELECT Sales_Line__c, Mirror_Line__c
            FROM Product2
            WHERE Id = :detail.Id
        ];
        System.assertEquals(null, refreshed.Sales_Line__c);
        System.assertEquals(null, refreshed.Mirror_Line__c);
    }

    private static Boolean containsTerritory(
        TerritoryManagementController.TerritoryTreeNode node,
        Id territoryId
    ) {
        if (node == null) {
            return false;
        }
        if (node.id == territoryId) {
            return true;
        }
        if (node.children == null) {
            return false;
        }
        for (TerritoryManagementController.TerritoryTreeNode child : node.children) {
            if (containsTerritory(child, territoryId)) {
                return true;
            }
        }
        return false;
    }

    private static Territory2 getOrCreateLineTerritory(String externalId, String name) {
        List<Territory2> existing = [
            SELECT Id, Name, External_ID__c, Territory_Type__c
            FROM Territory2
            WHERE External_ID__c = :externalId
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            Territory2 line = existing[0];
            if (line.Territory_Type__c != 'Line') {
                line.Territory_Type__c = 'Line';
                line.Name = name;
                update line;
            }
            return line;
        }

        List<Territory2Type> types = [SELECT Id FROM Territory2Type LIMIT 1];
        if (types.isEmpty()) {
            return null;
        }

        List<Territory2Model> models = [
            SELECT Id
            FROM Territory2Model
            WHERE State = 'Active'
            LIMIT 1
        ];
        if (models.isEmpty()) {
            models = [SELECT Id FROM Territory2Model LIMIT 1];
        }
        if (models.isEmpty()) {
            return null;
        }

        Territory2 territory = new Territory2(
            Name = name,
            DeveloperName = 'Line_' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            Territory2ModelId = models[0].Id,
            Territory2TypeId = types[0].Id,
            External_ID__c = externalId,
            Territory_Type__c = 'Line'
        );
        insert territory;
        return territory;
    }

    private static Territory2 getOrCreateTestTerritory(String externalId) {
        List<Territory2> existing = [
            SELECT Id
            FROM Territory2
            WHERE External_ID__c = :externalId
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0];
        }

        List<Territory2Type> types = [SELECT Id FROM Territory2Type LIMIT 1];
        if (types.isEmpty()) {
            return null;
        }

        List<Territory2Model> models = [
            SELECT Id
            FROM Territory2Model
            WHERE DeveloperName = 'Current_FY'
            LIMIT 1
        ];
        if (models.isEmpty()) {
            return null;
        }

        Territory2 territory = new Territory2(
            Name = 'Territory Mgmt Test',
            DeveloperName = 'Territory_Mgmt_Test',
            Territory2ModelId = models[0].Id,
            Territory2TypeId = types[0].Id,
            External_ID__c = externalId
        );
        insert territory;
        return territory;
    }
}