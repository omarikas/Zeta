/**
 * Aura/LWC + VF entry points for the Pending Payment org switch.
 */
public without sharing class PendingPaymentController {
  @AuraEnabled(cacheable=true)
  public static Boolean isPendingPayment() {
    return PendingPaymentService.isEnabled();
  }

  /** Non-cacheable for Utility Bar / navigation re-checks. */
  @AuraEnabled
  public static Boolean isPendingPaymentNow() {
    return PendingPaymentService.isEnabled();
  }

  public Boolean getIsPendingPayment() {
    return PendingPaymentService.isEnabled();
  }

  public String getWarningMessage() {
    return PendingPaymentService.WARNING_MESSAGE;
  }
}