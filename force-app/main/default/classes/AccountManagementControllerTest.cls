@IsTest
private class AccountManagementControllerTest {
    @IsTest
    static void coversWipeImportExportAndDuplicates() {
        System.assertEquals('Orthopaedics', AccountMasterImportUtil.mapSpecialty('Ortho'));
        System.assertEquals(null, AccountMasterImportUtil.mapSpecialty(''));
        System.assertEquals('A', AccountMasterImportUtil.mapTierFromClass('AA3'));
        System.assertEquals(null, AccountMasterImportUtil.mapTierFromClass(''));
        System.assertEquals('DOC-921', AccountMasterImportUtil.doctorExternalId('921'));
        System.assertEquals('CLINIC-16793', AccountMasterImportUtil.clinicExternalId('16793'));
        System.assert(
            AccountMasterImportUtil.affiliationExternalId('921', 'CLINIC-16793').contains('AFF-')
        );
        System.assertEquals(true, AccountMasterImportUtil.toBoolean('yes', false));
        System.assertEquals(false, AccountMasterImportUtil.toBoolean('no', true));
        System.assertEquals(true, AccountMasterImportUtil.toBoolean(true, false));
        System.assertNotEquals(null, AccountMasterImportUtil.normalizePhone('1009086222'));
        System.assertEquals(null, AccountMasterImportUtil.normalizePhone(''));

        Account probe = new Account();
        AccountMasterImportUtil.splitPersonName('Ahmed El Khatib', probe);
        System.assertEquals('Ahmed', probe.FirstName);
        System.assert(String.isNotBlank(probe.LastName));
        Account probe2 = new Account();
        AccountMasterImportUtil.splitPersonName('SingleName', probe2);
        System.assertEquals('SingleName', probe2.LastName);
        Account probe3 = new Account();
        AccountMasterImportUtil.splitPersonName('', probe3);
        System.assertEquals('Unknown', probe3.LastName);

        Id hcoRt = AccountMasterImportUtil.recordTypeId('Institution_HCO', false);
        Id hcpRt = AccountMasterImportUtil.hcpRecordTypeId();
        Boolean hcpIsPerson = AccountMasterImportUtil.isPersonRecordType(hcpRt);

        Account clinic = new Account(
            RecordTypeId = hcoRt,
            Name = 'Clinic Test 16793',
            External_ID__c = 'CLINIC-16793',
            BillingCity = 'Manial',
            BillingStreet = 'Manial St',
            BillingCountry = 'Egypt',
            Account_Status__c = 'Active'
        );
        insert clinic;

        Account hcp = new Account(RecordTypeId = hcpRt, External_ID__c = 'DOC-921', Account_Status__c = 'Active');
        if (hcpIsPerson) {
            hcp.FirstName = 'Ahmed';
            hcp.LastName = 'El Khatib';
        } else {
            hcp.Name = 'Ahmed El Khatib';
        }
        insert hcp;

        AccountManagementController.OrgRow orgRow = new AccountManagementController.OrgRow();
        orgRow.code = '921 - 16793';
        orgRow.doctorCode = '921';
        orgRow.doctorClinicId = '16793';
        orgRow.name = 'Ahmed El Khatib';
        orgRow.organizationTypeName = 'Doctor';
        orgRow.specialty = 'Ortho';
        orgRow.area = 'Manial';
        orgRow.address = 'Manial St Salam Pharmacy';
        orgRow.customerClass = 'AA3';
        orgRow.active = true;

        AccountManagementController.DoctorRow docRow = new AccountManagementController.DoctorRow();
        docRow.code = '921';
        docRow.doctor = 'Ahmed El Khatib';
        docRow.specialty = 'Ortho';
        docRow.customerClass = 'A3';
        docRow.isActive = true;
        docRow.mobile = '1009086222';

        AccountManagementController.AffiliationRow affRow = new AccountManagementController.AffiliationRow();
        affRow.doctorCode = '921';
        affRow.clinicId = '16793';

        AccountManagementController.OrgRow hospital = new AccountManagementController.OrgRow();
        hospital.code = 'H456';
        hospital.name = 'Nahda Medical Center';
        hospital.organizationTypeName = 'Hospital';
        hospital.area = 'Salam';
        hospital.address = 'Nahda Salam';
        hospital.customerClass = 'AA1';
        hospital.active = true;

        Test.startTest();
        AccountManagementController.ChunkResult orgResult =
            AccountManagementController.upsertOrganizationChunk(
                new List<AccountManagementController.OrgRow>{ orgRow, hospital },
                true
            );
        AccountManagementController.ChunkResult docResult =
            AccountManagementController.upsertDoctorChunk(
                new List<AccountManagementController.DoctorRow>{ docRow },
                false
            );
        AccountManagementController.ChunkResult affResult =
            AccountManagementController.upsertAffiliationChunk(
                new List<AccountManagementController.AffiliationRow>{ affRow }
            );
        AccountManagementController.ExportPayload accounts =
            AccountManagementController.exportAccounts(null, 100);
        AccountManagementController.ExportPayload affiliations =
            AccountManagementController.exportAffiliations(null, 100);
        AccountManagementController.JobStatus counts = AccountManagementController.getCounts();
        AccountManagementController.JobStatus wipe = AccountManagementController.startWipe();
        AccountManagementController.getWipeStatus(wipe.jobId);
        AccountManagementController.findPotentialDuplicates('Nahda Medical Center', 'Salam', 'Nahda');
        Test.stopTest();

        System.assert(orgResult.successCount >= 1, 'org upsert ' + String.valueOf(orgResult.errors));
        System.assert(docResult.successCount >= 1, 'doctor upsert ' + String.valueOf(docResult.errors));
        System.assert(affResult.successCount >= 1, 'affiliation upsert ' + String.valueOf(affResult.errors));
        System.assert(!accounts.accounts.isEmpty(), 'export accounts');
        System.assert(!affiliations.affiliations.isEmpty(), 'export affiliations');
        System.assertNotEquals(null, counts.accountCount);
        System.assertNotEquals(null, wipe.jobId);
    }
}