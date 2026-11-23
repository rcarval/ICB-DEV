trigger ICBFS_CalificacionLeadTrigger on ICBFS_Calificacion_Lead__e (after insert) {
    ICBFS_CalificacionEventHandler.afterInsert(Trigger.new);
}