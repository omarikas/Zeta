@IsTest private class S_EmployeeTimeCardServiceTest {
  @IsTest static void smoke() {
    EmployeeTimeCardService.ensureMonthlyTimeCard(UserInfo.getUserId(), Date.today().toStartOfMonth());
    EmployeeTimeCardService.ensureMonthlyTimeCard(UserInfo.getUserId(), Date.today().toStartOfMonth(), true);
    EmployeeTimeCardService.syncAccountTargets(null);
    EmployeeTimeCardService.syncAccountTargetsForTimeCards(UserInfo.getUserId(), new List<Id>());
    EmployeeTimeCardService.mapFrequencyPicklist('Weekly');
    EmployeeTimeCardService.applyVisionWeights(null, new Map<String,Object>());
  }
}