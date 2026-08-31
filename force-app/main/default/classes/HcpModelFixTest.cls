@IsTest
private class HcpModelFixTest {
  @IsTest
  static void clinicBatch_setsHcpRecordTypeAndSubtype() {
    Id hcoRt = [
      SELECT Id
      FROM RecordType
      WHERE SObjectType = 'Account' AND DeveloperName = 'Institution_HCO' AND IsPersonType = FALSE
      LIMIT 1
    ]
    .Id;
    Account clinic = new Account(
      Name = 'Clinic Model Fix',
      RecordTypeId = hcoRt,
      External_ID__c = 'CLINIC-MODELFIX1',
      Institution_Type__c = 'Clinic'
    );
    insert clinic;

    Test.startTest();
    Database.executeBatch(new ClinicHcpSubtypeBatch(), 50);
    Test.stopTest();

    Account refreshed = [
      SELECT RecordType.DeveloperName, Institution_Type__c, IsPersonAccount
      FROM Account
      WHERE Id = :clinic.Id
    ];
    System.assertEquals(false, refreshed.IsPersonAccount);
    System.assertEquals('Clinic', refreshed.Institution_Type__c);
    System.assertEquals('Institution_HCO', refreshed.RecordType.DeveloperName);
  }

  @IsTest
  static void doctorBatch_stampsDoctorSubtype() {
    Id hcpBizRt = [
      SELECT Id
      FROM RecordType
      WHERE
        SObjectType = 'Account'
        AND DeveloperName = 'Medical_Professional_HCP'
        AND IsPersonType = FALSE
      LIMIT 1
    ]
    .Id;
    Account doctor = new Account(
      Name = 'Ahmed Test Doctor',
      RecordTypeId = hcpBizRt,
      External_ID__c = 'DOC-MODELFIX1'
    );
    insert doctor;

    Test.startTest();
    Database.executeBatch(new DoctorSubtypeStampBatch(), 10);
    Test.stopTest();

    System.assertEquals(
      'Doctor',
      [SELECT Institution_Type__c FROM Account WHERE Id = :doctor.Id].Institution_Type__c
    );
  }

  @IsTest
  static void importUtil_helpers() {
    Account person = new Account();
    AccountMasterImportUtil.splitPersonName('Ahmed Khaled Doctor', person);
    System.assertEquals('Ahmed', person.FirstName);
    System.assertEquals('Khaled Doctor', person.LastName);
    AccountMasterImportUtil.splitPersonName('Single', person);
    System.assertEquals('Single', person.LastName);

    System.assertEquals('DOC-921', AccountMasterImportUtil.doctorExternalId('921'));
    System.assertEquals('CLINIC-16793', AccountMasterImportUtil.clinicExternalId('16793'));
    System.assertEquals(
      'AFF-DOC-921-CLINIC-16793',
      AccountMasterImportUtil.affiliationExternalId('921', 'CLINIC-16793')
    );
    System.assertEquals('Cardiology', AccountMasterImportUtil.mapSpecialty('Cardio'));
    System.assertEquals(null, AccountMasterImportUtil.mapSpecialty(null));
    System.assertEquals('A', AccountMasterImportUtil.mapTierFromClass('AA1'));
    System.assertEquals(null, AccountMasterImportUtil.mapTierFromClass(''));
    System.assertEquals('+201234567890', AccountMasterImportUtil.normalizePhone('1234567890'));
    System.assertEquals(null, AccountMasterImportUtil.normalizePhone(null));
    System.assertEquals(true, AccountMasterImportUtil.toBoolean(true, false));
    System.assertEquals(true, AccountMasterImportUtil.toBoolean('yes', false));
    System.assertEquals(false, AccountMasterImportUtil.toBoolean('0', true));
    System.assertEquals(true, AccountMasterImportUtil.toBoolean(null, true));
    System.assertNotEquals(null, AccountMasterImportUtil.recordTypeId('Institution_HCO'));
    System.assertNotEquals(null, AccountMasterImportUtil.recordTypeId('Institution_HCO', false));
    System.assertNotEquals(null, AccountMasterImportUtil.clinicHcpRecordTypeId());
    System.assertEquals(
      false,
      AccountMasterImportUtil.isPersonRecordType(AccountMasterImportUtil.clinicHcpRecordTypeId())
    );
    System.assertEquals(true, AccountMasterImportUtil.isWorkplaceDoctorName('ABB'));
    System.assertEquals(true, AccountMasterImportUtil.isWorkplaceDoctorName('قسم الباطنه'));
    System.assertEquals(false, AccountMasterImportUtil.isWorkplaceDoctorName('احمد الخطيب'));
    System.assertEquals(
      'احمد شريف',
      AccountMasterImportUtil.cleanPrefixedAccountName('1000027554_احمد شريف')
    );
    Id hcpRt = AccountMasterImportUtil.hcpRecordTypeId();
    System.assertNotEquals(null, hcpRt);
    AccountMasterImportUtil.isPersonRecordType(hcpRt);
    AccountMasterImportUtil.isPersonRecordType(null);
  }
}