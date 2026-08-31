/**
 * Reads org-level Pending Payment switch from Hierarchy Custom Setting.
 */
public without sharing class PendingPaymentService {
  public static final String WARNING_MESSAGE =
    'Salesforce invoice pending payment, your org is at risk of being shut-down, please share proof of payment with your account manager';

  public static Boolean isEnabled() {
    Org_Feature_Switch__c cfg = Org_Feature_Switch__c.getOrgDefaults();
    return cfg != null && cfg.Pending_Payment__c == true;
  }

  /**
   * Upserts org defaults with Pending Payment checked (ops / post-deploy seed).
   */
  public static void enablePendingPayment() {
    Org_Feature_Switch__c cfg = Org_Feature_Switch__c.getOrgDefaults();
    cfg.Pending_Payment__c = true;
    upsert cfg;
  }
}