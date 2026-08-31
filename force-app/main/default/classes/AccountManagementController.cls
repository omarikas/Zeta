/**
 * Admin Console Account Management: wipe, chunked Excel load, export, duplicate scan.
 */
public with sharing class AccountManagementController {
    public class ChunkResult {
        @AuraEnabled public Integer successCount;
        @AuraEnabled public Integer errorCount;
        @AuraEnabled public Integer skippedCount;
        @AuraEnabled public List<String> errors;
        @AuraEnabled public List<DuplicateHit> duplicates;
    }

    public class DuplicateHit {
        @AuraEnabled public String incomingExternalId;
        @AuraEnabled public String incomingName;
        @AuraEnabled public Id existingId;
        @AuraEnabled public String existingName;
        @AuraEnabled public String existingExternalId;
        @AuraEnabled public String existingCity;
        @AuraEnabled public String matchReason;
    }

    public class JobStatus {
        @AuraEnabled public Id jobId;
        @AuraEnabled public String status;
        @AuraEnabled public String phase;
        @AuraEnabled public Integer jobItemsProcessed;
        @AuraEnabled public Integer totalJobItems;
        @AuraEnabled public Integer numberOfErrors;
        @AuraEnabled public String extendedStatus;
        @AuraEnabled public Long accountCount;
        @AuraEnabled public Long affiliationCount;
    }

    public class ExportPayload {
        @AuraEnabled public List<Map<String, Object>> accounts;
        @AuraEnabled public List<Map<String, Object>> affiliations;
        @AuraEnabled public Boolean hasMore;
        @AuraEnabled public String nextAccountId;
        @AuraEnabled public String nextAffiliationId;
    }

    public class OrgRow {
        @AuraEnabled public String code;
        @AuraEnabled public String doctorCode;
        @AuraEnabled public String doctorClinicId;
        @AuraEnabled public String name;
        @AuraEnabled public String accountName;
        @AuraEnabled public String organizationTypeName;
        @AuraEnabled public String specialty;
        @AuraEnabled public String area;
        @AuraEnabled public String address;
        @AuraEnabled public String customerClass;
        @AuraEnabled public Object active;
        @AuraEnabled public String telephone;
        @AuraEnabled public String email;
    }

    public class DoctorRow {
        @AuraEnabled public String code;
        @AuraEnabled public String doctor;
        @AuraEnabled public String specialty;
        @AuraEnabled public String customerClass;
        @AuraEnabled public Object isActive;
        @AuraEnabled public String mobile;
        @AuraEnabled public String email;
    }

    public class AffiliationRow {
        @AuraEnabled public String doctorCode;
        @AuraEnabled public String clinicId;
        @AuraEnabled public String relatedExternalId;
        @AuraEnabled public String accountName;
        @AuraEnabled public Object isPrimary;
    }

    @AuraEnabled
    public static JobStatus getCounts() {
        JobStatus status = new JobStatus();
        status.accountCount = [SELECT COUNT() FROM Account];
        status.affiliationCount = [SELECT COUNT() FROM Account_Affiliation__c];
        return status;
    }

    @AuraEnabled
    public static JobStatus startWipe() {
        Id jobId = Database.executeBatch(new AccountWipeBatch(), 200);
        JobStatus status = new JobStatus();
        status.jobId = jobId;
        status.status = 'Queued';
        status.phase = 'AFFILIATIONS';
        return status;
    }

    @AuraEnabled
    public static JobStatus getWipeStatus(Id jobId) {
        JobStatus status = new JobStatus();
        status.accountCount = [SELECT COUNT() FROM Account];
        status.affiliationCount = [SELECT COUNT() FROM Account_Affiliation__c];

        List<AsyncApexJob> jobs = [
            SELECT Id, Status, JobItemsProcessed, TotalJobItems, NumberOfErrors, ExtendedStatus, ApexClass.Name, CreatedDate
            FROM AsyncApexJob
            WHERE Id = :jobId
               OR (ApexClass.Name = 'AccountWipeBatch' AND CreatedDate = LAST_N_DAYS:1)
            ORDER BY CreatedDate DESC
            LIMIT 20
        ];
        if (jobs.isEmpty()) {
            status.status = 'Unknown';
            return status;
        }

        AsyncApexJob latest = jobs[0];
        Boolean anyProcessing = false;
        Boolean anyFailed = false;
        for (AsyncApexJob j : jobs) {
            if (j.ApexClass.Name != 'AccountWipeBatch') {
                continue;
            }
            if (j.Status == 'Queued' || j.Status == 'Preparing' || j.Status == 'Processing' || j.Status == 'Holding') {
                anyProcessing = true;
                latest = j;
                break;
            }
            if (j.Status == 'Failed' || j.Status == 'Aborted') {
                anyFailed = true;
            }
        }

        status.jobId = latest.Id;
        status.jobItemsProcessed = latest.JobItemsProcessed;
        status.totalJobItems = latest.TotalJobItems;
        status.numberOfErrors = latest.NumberOfErrors;
        status.extendedStatus = latest.ExtendedStatus;
        if (anyProcessing) {
            status.status = 'Processing';
        } else if (anyFailed && status.accountCount > 0) {
            status.status = 'Failed';
        } else if (status.accountCount == 0) {
            status.status = 'Completed';
        } else {
            status.status = latest.Status;
        }
        return status;
    }

    @AuraEnabled
    public static ChunkResult upsertOrganizationChunk(List<OrgRow> rows, Boolean checkDuplicates) {
        ChunkResult result = emptyResult();
        if (rows == null || rows.isEmpty()) {
            return result;
        }

        Id hcoRt = AccountMasterImportUtil.recordTypeId('Institution_HCO');
        Id pharmacyRt = AccountMasterImportUtil.recordTypeId('Pharmacy');
        Id distributorRt = AccountMasterImportUtil.recordTypeId('Distributor');

        Map<String, Account> byExt = new Map<String, Account>();
        for (OrgRow row : rows) {
            String typeName = row.organizationTypeName == null ? '' : row.organizationTypeName.trim();
            if (typeName.equalsIgnoreCase('Doctor')) {
                String clinicId = AccountMasterImportUtil.normalizeCode(row.doctorClinicId);
                if (String.isBlank(clinicId)) {
                    result.skippedCount++;
                    continue;
                }
                String ext = AccountMasterImportUtil.clinicExternalId(clinicId);
                String doctorLabel = String.isBlank(row.doctorCode) ? row.name : row.name;
                String clinicName = AccountMasterImportUtil.clinicDisplayName(
                    doctorLabel,
                    row.area,
                    clinicId,
                    row.address
                );
                Account acc = new Account(
                    RecordTypeId = AccountMasterImportUtil.clinicHcpRecordTypeId(),
                    Name = clinicName,
                    External_ID__c = ext,
                    Institution_Type__c = 'Clinic',
                    BillingStreet = blankToNull(row.address),
                    BillingCity = blankToNull(row.area),
                    BillingCountry = AccountMasterImportUtil.COUNTRY,
                    Customer_Class__c = blankToNull(row.customerClass),
                    Tier__c = AccountMasterImportUtil.mapTierFromClass(row.customerClass),
                    Account_Status__c = AccountMasterImportUtil.toBoolean(row.active, true) ? 'Active' : 'Inactive',
                    Phone = AccountMasterImportUtil.normalizePhone(row.telephone)
                );
                byExt.put(ext, acc);
            } else if (typeName.equalsIgnoreCase('Pharmacy')) {
                String code = AccountMasterImportUtil.normalizeCode(row.code);
                String cleanName = AccountMasterImportUtil.cleanPrefixedAccountName(row.name);
                if (String.isBlank(code) || String.isBlank(cleanName)) {
                    result.skippedCount++;
                    continue;
                }
                Account acc = new Account(
                    RecordTypeId = pharmacyRt,
                    Name = cleanName.left(255),
                    External_ID__c = code,
                    BillingStreet = blankToNull(row.address),
                    BillingCity = blankToNull(row.area),
                    BillingCountry = AccountMasterImportUtil.COUNTRY,
                    Customer_Class__c = blankToNull(row.customerClass),
                    Tier__c = AccountMasterImportUtil.mapTierFromClass(row.customerClass),
                    Account_Status__c = AccountMasterImportUtil.toBoolean(row.active, true) ? 'Active' : 'Inactive',
                    Phone = AccountMasterImportUtil.normalizePhone(row.telephone)
                );
                byExt.put(code, acc);
            } else if (typeName.equalsIgnoreCase('Distributor')) {
                String code = AccountMasterImportUtil.normalizeCode(row.code);
                if (String.isBlank(code) || String.isBlank(row.name)) {
                    result.skippedCount++;
                    continue;
                }
                Account acc = new Account(
                    RecordTypeId = distributorRt,
                    Name = row.name.left(255),
                    External_ID__c = code,
                    BillingStreet = blankToNull(row.address),
                    BillingCity = blankToNull(row.area),
                    BillingCountry = AccountMasterImportUtil.COUNTRY,
                    Customer_Class__c = blankToNull(row.customerClass),
                    Tier__c = AccountMasterImportUtil.mapTierFromClass(row.customerClass),
                    Account_Status__c = AccountMasterImportUtil.toBoolean(row.active, true) ? 'Active' : 'Inactive',
                    Phone = AccountMasterImportUtil.normalizePhone(row.telephone)
                );
                byExt.put(code, acc);
            } else if (typeName.equalsIgnoreCase('Hospital') || typeName.equalsIgnoreCase('Contract')) {
                String code = AccountMasterImportUtil.normalizeCode(row.code);
                if (String.isBlank(code) || String.isBlank(row.name)) {
                    result.skippedCount++;
                    continue;
                }
                Account acc = new Account(
                    RecordTypeId = hcoRt,
                    Name = row.name.left(255),
                    External_ID__c = code,
                    Institution_Type__c = typeName.equalsIgnoreCase('Hospital') ? 'Hospital' : 'Contract',
                    BillingStreet = blankToNull(row.address),
                    BillingCity = blankToNull(row.area),
                    BillingCountry = AccountMasterImportUtil.COUNTRY,
                    Customer_Class__c = blankToNull(row.customerClass),
                    Tier__c = AccountMasterImportUtil.mapTierFromClass(row.customerClass),
                    Account_Status__c = AccountMasterImportUtil.toBoolean(row.active, true) ? 'Active' : 'Inactive',
                    Phone = AccountMasterImportUtil.normalizePhone(row.telephone)
                );
                byExt.put(code, acc);
            } else {
                result.skippedCount++;
            }
        }

        if (checkDuplicates == true) {
            result.duplicates = findDuplicatesForAccounts(byExt.values());
        }

        upsertAccounts(byExt.values(), result);
        return result;
    }

    @AuraEnabled
    public static ChunkResult upsertDoctorChunk(List<DoctorRow> rows, Boolean checkDuplicates) {
        ChunkResult result = emptyResult();
        if (rows == null || rows.isEmpty()) {
            return result;
        }

        Id hcpRt = AccountMasterImportUtil.hcpRecordTypeId();
        Boolean hcpIsPerson = AccountMasterImportUtil.isPersonRecordType(hcpRt);
        Map<String, Account> byExt = new Map<String, Account>();
        Set<String> seenCodes = new Set<String>();

        for (DoctorRow row : rows) {
            String code = AccountMasterImportUtil.normalizeCode(row.code);
            if (String.isBlank(code) || String.isBlank(row.doctor)) {
                result.skippedCount++;
                continue;
            }
            if (seenCodes.contains(code)) {
                result.skippedCount++;
                result.errors.add('Duplicate doctor code in chunk skipped: ' + code);
                continue;
            }
            if (AccountMasterImportUtil.isWorkplaceDoctorName(row.doctor)) {
                result.skippedCount++;
                result.errors.add('Skipped workplace-as-HCP: ' + code + ' ' + row.doctor);
                continue;
            }
            seenCodes.add(code);
            String ext = AccountMasterImportUtil.doctorExternalId(code);
            Account acc = new Account(
                RecordTypeId = hcpRt,
                External_ID__c = ext,
                Institution_Type__c = 'Doctor',
                Customer_Class__c = blankToNull(row.customerClass),
                Tier__c = AccountMasterImportUtil.mapTierFromClass(row.customerClass),
                Account_Status__c = AccountMasterImportUtil.toBoolean(row.isActive, true) ? 'Active' : 'Inactive',
                BillingCountry = AccountMasterImportUtil.COUNTRY
            );
            // Specialty_1__c skipped: PersonAccount RT picklist is narrower than Medical_Specialty GVS.
            if (hcpIsPerson) {
                AccountMasterImportUtil.splitPersonName(row.doctor, acc);
                acc.PersonMobilePhone = AccountMasterImportUtil.normalizePhone(row.mobile);
                acc.PersonEmail = blankToNull(row.email);
            } else {
                acc.Name = row.doctor.left(255);
                acc.Phone = AccountMasterImportUtil.normalizePhone(row.mobile);
            }
            byExt.put(ext, acc);
        }

        if (checkDuplicates == true) {
            result.duplicates = findDuplicatesForAccounts(byExt.values());
        }

        upsertAccounts(byExt.values(), result);
        return result;
    }

    @AuraEnabled
    public static ChunkResult upsertAffiliationChunk(List<AffiliationRow> rows) {
        ChunkResult result = emptyResult();
        if (rows == null || rows.isEmpty()) {
            return result;
        }

        Set<String> accountExtIds = new Set<String>();
        Set<String> hcoNames = new Set<String>();
        for (AffiliationRow row : rows) {
            String docCode = AccountMasterImportUtil.normalizeCode(row.doctorCode);
            if (String.isNotBlank(docCode)) {
                accountExtIds.add(AccountMasterImportUtil.doctorExternalId(docCode));
            }
            if (String.isNotBlank(row.clinicId)) {
                accountExtIds.add(AccountMasterImportUtil.clinicExternalId(row.clinicId));
            }
            if (String.isNotBlank(row.relatedExternalId)) {
                accountExtIds.add(AccountMasterImportUtil.normalizeCode(row.relatedExternalId));
            }
            if (String.isNotBlank(row.accountName)) {
                hcoNames.add(row.accountName.trim());
            }
        }

        Map<String, Id> accountByExt = new Map<String, Id>();
        for (Account a : [
            SELECT Id, External_ID__c
            FROM Account
            WHERE External_ID__c IN :accountExtIds
            WITH SYSTEM_MODE
        ]) {
            accountByExt.put(a.External_ID__c, a.Id);
        }

        Map<String, Id> accountByName = new Map<String, Id>();
        if (!hcoNames.isEmpty()) {
            for (Account a : [
                SELECT Id, Name, External_ID__c
                FROM Account
                WHERE Name IN :hcoNames
                  AND RecordType.DeveloperName IN ('Institution_HCO', 'Pharmacy', 'Distributor')
                WITH SYSTEM_MODE
            ]) {
                accountByName.put(a.Name.trim(), a.Id);
            }
        }

        Map<String, Account_Affiliation__c> byExt = new Map<String, Account_Affiliation__c>();
        for (AffiliationRow row : rows) {
            String docCode = AccountMasterImportUtil.normalizeCode(row.doctorCode);
            if (String.isBlank(docCode)) {
                result.skippedCount++;
                continue;
            }
            Id hcpId = accountByExt.get(AccountMasterImportUtil.doctorExternalId(docCode));
            if (hcpId == null) {
                result.errorCount++;
                result.errors.add('HCP not found for doctor ' + docCode);
                continue;
            }

            Id relatedId;
            String relatedExt;
            if (String.isNotBlank(row.clinicId)) {
                relatedExt = AccountMasterImportUtil.clinicExternalId(row.clinicId);
                relatedId = accountByExt.get(relatedExt);
            } else if (String.isNotBlank(row.relatedExternalId)) {
                relatedExt = AccountMasterImportUtil.normalizeCode(row.relatedExternalId);
                relatedId = accountByExt.get(relatedExt);
            } else if (String.isNotBlank(row.accountName)) {
                relatedId = accountByName.get(row.accountName.trim());
                relatedExt = 'NAME-' + row.accountName.trim();
            }

            if (relatedId == null) {
                result.skippedCount++;
                continue;
            }

            String affExt = AccountMasterImportUtil.affiliationExternalId(docCode, relatedExt);
            byExt.put(
                affExt,
                new Account_Affiliation__c(
                    External_ID__c = affExt,
                    Primary_Account__c = hcpId,
                    Related_Account__c = relatedId,
                    Affiliation_Type__c = 'Practice',
                    Role__c = 'Physician',
                    Is_Active__c = true,
                    Is_Primary__c = AccountMasterImportUtil.toBoolean(row.isPrimary, false)
                )
            );
        }

        if (byExt.isEmpty()) {
            return result;
        }

        Database.DMLOptions dml = new Database.DMLOptions();
        dml.DuplicateRuleHeader.allowSave = true;
        dml.optAllOrNone = false;

        List<Account_Affiliation__c> records = byExt.values();
        Database.UpsertResult[] urs = Database.upsert(records, Account_Affiliation__c.External_ID__c, false, AccessLevel.SYSTEM_MODE);
        for (Integer i = 0; i < urs.size(); i++) {
            if (urs[i].isSuccess()) {
                result.successCount++;
            } else {
                result.errorCount++;
                if (result.errors.size() < 50) {
                    result.errors.add(urs[i].getErrors()[0].getMessage());
                }
            }
        }
        return result;
    }

    @AuraEnabled
    public static List<DuplicateHit> findPotentialDuplicates(String name, String city, String street) {
        List<Account> probe = new List<Account>{
            new Account(Name = name, BillingCity = city, BillingStreet = street)
        };
        return findDuplicatesForAccounts(probe);
    }

    @AuraEnabled
    public static ExportPayload exportAccounts(String afterId, Integer pageSize) {
        Integer lim = pageSize == null || pageSize <= 0 ? 2000 : Math.min(pageSize, 5000);
        ExportPayload payload = new ExportPayload();
        payload.accounts = new List<Map<String, Object>>();
        payload.affiliations = new List<Map<String, Object>>();

        String soql =
            'SELECT Id, Name, FirstName, LastName, External_ID__c, RecordType.DeveloperName, RecordType.Name, ' +
            'Institution_Type__c, Specialty_1__c, Customer_Class__c, Tier__c, Account_Status__c, ' +
            'BillingStreet, BillingCity, BillingCountry, Phone, PersonMobilePhone, PersonEmail, IsPersonAccount ' +
            'FROM Account ';
        if (String.isNotBlank(afterId)) {
            soql += 'WHERE Id > :afterId ';
        }
        soql += 'ORDER BY Id ASC LIMIT :lim';

        List<Account> accounts = Database.query(soql, AccessLevel.SYSTEM_MODE);
        for (Account a : accounts) {
            Map<String, Object> row = new Map<String, Object>{
                'Id' => a.Id,
                'External_ID__c' => a.External_ID__c,
                'Name' => a.IsPersonAccount ? ((a.FirstName == null ? '' : a.FirstName + ' ') + a.LastName).trim() : a.Name,
                'RecordType' => a.RecordType.DeveloperName,
                'RecordTypeLabel' => a.RecordType.Name,
                'Institution_Type__c' => a.Institution_Type__c,
                'Specialty_1__c' => a.Specialty_1__c,
                'Customer_Class__c' => a.Customer_Class__c,
                'Tier__c' => a.Tier__c,
                'Account_Status__c' => a.Account_Status__c,
                'BillingStreet' => a.BillingStreet,
                'BillingCity' => a.BillingCity,
                'BillingCountry' => a.BillingCountry,
                'Phone' => a.IsPersonAccount ? a.PersonMobilePhone : a.Phone,
                'Email' => a.PersonEmail
            };
            payload.accounts.add(row);
        }
        payload.hasMore = accounts.size() == lim;
        payload.nextAccountId = accounts.isEmpty() ? afterId : accounts[accounts.size() - 1].Id;
        return payload;
    }

    @AuraEnabled
    public static ExportPayload exportAffiliations(String afterId, Integer pageSize) {
        Integer lim = pageSize == null || pageSize <= 0 ? 2000 : Math.min(pageSize, 5000);
        ExportPayload payload = new ExportPayload();
        payload.accounts = new List<Map<String, Object>>();
        payload.affiliations = new List<Map<String, Object>>();

        String soql =
            'SELECT Id, External_ID__c, Affiliation_Type__c, Role__c, Is_Active__c, ' +
            'Primary_Account__r.External_ID__c, Primary_Account__r.Name, ' +
            'Related_Account__r.External_ID__c, Related_Account__r.Name ' +
            'FROM Account_Affiliation__c ';
        if (String.isNotBlank(afterId)) {
            soql += 'WHERE Id > :afterId ';
        }
        soql += 'ORDER BY Id ASC LIMIT :lim';

        List<Account_Affiliation__c> rows = Database.query(soql, AccessLevel.SYSTEM_MODE);
        for (Account_Affiliation__c a : rows) {
            payload.affiliations.add(
                new Map<String, Object>{
                    'Id' => a.Id,
                    'External_ID__c' => a.External_ID__c,
                    'Affiliation_Type__c' => a.Affiliation_Type__c,
                    'Role__c' => a.Role__c,
                    'Is_Active__c' => a.Is_Active__c,
                    'Primary_External_ID__c' => a.Primary_Account__r.External_ID__c,
                    'Primary_Name' => a.Primary_Account__r.Name,
                    'Related_External_ID__c' => a.Related_Account__r.External_ID__c,
                    'Related_Name' => a.Related_Account__r.Name
                }
            );
        }
        payload.hasMore = rows.size() == lim;
        payload.nextAffiliationId = rows.isEmpty() ? afterId : rows[rows.size() - 1].Id;
        return payload;
    }

    private static ChunkResult emptyResult() {
        ChunkResult result = new ChunkResult();
        result.successCount = 0;
        result.errorCount = 0;
        result.skippedCount = 0;
        result.errors = new List<String>();
        result.duplicates = new List<DuplicateHit>();
        return result;
    }

    private static String blankToNull(String value) {
        return String.isBlank(value) ? null : value.trim();
    }

    private static void upsertAccounts(List<Account> accounts, ChunkResult result) {
        if (accounts == null || accounts.isEmpty()) {
            return;
        }
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.DuplicateRuleHeader.allowSave = true;
        dml.optAllOrNone = false;
        for (Account a : accounts) {
            a.setOptions(dml);
        }

        Database.UpsertResult[] urs = Database.upsert(accounts, Account.External_ID__c, false, AccessLevel.SYSTEM_MODE);
        for (Integer i = 0; i < urs.size(); i++) {
            if (urs[i].isSuccess()) {
                result.successCount++;
            } else {
                result.errorCount++;
                if (result.errors.size() < 50) {
                    String msg = urs[i].getErrors().isEmpty()
                        ? 'upsert failed'
                        : urs[i].getErrors()[0].getMessage();
                    result.errors.add((accounts[i].External_ID__c == null ? '' : accounts[i].External_ID__c + ': ') + msg);
                }
            }
        }
    }

    private static List<DuplicateHit> findDuplicatesForAccounts(List<Account> incoming) {
        List<DuplicateHit> hits = new List<DuplicateHit>();
        if (incoming == null || incoming.isEmpty()) {
            return hits;
        }

        Set<String> names = new Set<String>();
        Set<String> cities = new Set<String>();
        for (Account a : incoming) {
            String n = displayName(a);
            if (String.isNotBlank(n)) {
                names.add(n);
            }
            if (String.isNotBlank(a.BillingCity)) {
                cities.add(a.BillingCity.trim());
            }
        }
        if (names.isEmpty()) {
            return hits;
        }

        Map<String, List<Account>> existingByNameCity = new Map<String, List<Account>>();
        for (Account existing : [
            SELECT Id, Name, FirstName, LastName, External_ID__c, BillingCity, BillingStreet, IsPersonAccount
            FROM Account
            WHERE Name IN :names
               OR (IsPersonAccount = TRUE AND LastName IN :names)
            WITH SYSTEM_MODE
            LIMIT 5000
        ]) {
            String key = normalizeKey(displayName(existing), existing.BillingCity);
            if (!existingByNameCity.containsKey(key)) {
                existingByNameCity.put(key, new List<Account>());
            }
            existingByNameCity.get(key).add(existing);
        }

        for (Account a : incoming) {
            String key = normalizeKey(displayName(a), a.BillingCity);
            List<Account> matches = existingByNameCity.get(key);
            if (matches == null) {
                continue;
            }
            for (Account existing : matches) {
                if (a.External_ID__c != null && a.External_ID__c == existing.External_ID__c) {
                    continue;
                }
                Boolean streetMatch =
                    String.isBlank(a.BillingStreet) ||
                    String.isBlank(existing.BillingStreet) ||
                    normalizeText(a.BillingStreet) == normalizeText(existing.BillingStreet) ||
                    normalizeText(a.BillingStreet).contains(normalizeText(existing.BillingStreet)) ||
                    normalizeText(existing.BillingStreet).contains(normalizeText(a.BillingStreet));
                if (!streetMatch) {
                    continue;
                }
                DuplicateHit hit = new DuplicateHit();
                hit.incomingExternalId = a.External_ID__c;
                hit.incomingName = displayName(a);
                hit.existingId = existing.Id;
                hit.existingName = displayName(existing);
                hit.existingExternalId = existing.External_ID__c;
                hit.existingCity = existing.BillingCity;
                hit.matchReason = 'Name + location';
                hits.add(hit);
                if (hits.size() >= 100) {
                    return hits;
                }
            }
        }
        return hits;
    }

    private static String displayName(Account a) {
        if (a == null) {
            return null;
        }
        if (a.IsPersonAccount == true || (a.LastName != null && a.Name == null)) {
            String fn = a.FirstName == null ? '' : a.FirstName + ' ';
            return (fn + (a.LastName == null ? '' : a.LastName)).trim();
        }
        return a.Name;
    }

    private static String normalizeKey(String name, String city) {
        return normalizeText(name) + '|' + normalizeText(city);
    }

    private static String normalizeText(String value) {
        return value == null ? '' : value.trim().toLowerCase().replaceAll('\\s+', ' ');
    }
}