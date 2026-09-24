/**********************************************************************************
 * ICB_PIA_RegistrationQueueable
 * Ejecuta el callout PIA de forma asíncrona (compatible con record-triggered flow).
 * SEIDOR - Ticket 00026565
 **********************************************************************************/
public class ICB_PIA_RegistrationQueueable implements Queueable, Database.AllowsCallouts {

    private static final String LOG_PREFIX = '[ICB_PIA]';

    private final Id accountId;
    private final Boolean forceRetry;

    public ICB_PIA_RegistrationQueueable(Id accountId, Boolean forceRetry) {
        this.accountId = accountId;
        this.forceRetry = forceRetry == true;
    }

    public void execute(QueueableContext context) {
        System.debug(LoggingLevel.INFO, LOG_PREFIX + ' Queueable INICIO | cuenta=' + accountId + ' | forceRetry=' + forceRetry + ' | jobId=' + (context != null ? context.getJobId() : null));
        ICB_PIA_RegistrationService.RegistrationResult result =
            ICB_PIA_RegistrationService.registerAccount(accountId, forceRetry);
        System.debug(LoggingLevel.INFO, LOG_PREFIX + ' Queueable FIN | cuenta=' + accountId + ' | success=' + (result != null ? result.success : null) + ' | estado=' + (result != null ? result.estadoSolicitud : null) + ' | mensaje=' + (result != null ? result.mensaje : null));
    }
}