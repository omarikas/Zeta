public without sharing class ZetaOrganogramBrickLoadQueueable implements Queueable {
    public void execute(QueueableContext context) {
        ZetaOrganogramTerritoryLoader.LoadResult result =
            ZetaOrganogramTerritoryLoader.loadBricksAndQueueAlignments();
        System.debug(LoggingLevel.INFO, result.message);
        if (result.errors != null) {
            for (String err : result.errors) {
                System.debug(LoggingLevel.ERROR, err);
            }
        }
    }
}