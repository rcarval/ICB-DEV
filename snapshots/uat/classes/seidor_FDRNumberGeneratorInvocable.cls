public with sharing class seidor_FDRNumberGeneratorInvocable {

    // public class Input {
    //     @InvocableVariable(required=true)
    //     public Id caseId;
    // }

    // public class Output {
    //     @InvocableVariable
    //     public Integer generatedNumber;

    //     @InvocableVariable
    //     public Id contentDocumentId;

    //     @InvocableVariable
    //     public Boolean alreadyExists;  
    // }

    // @InvocableMethod(label='Generar Número FDR'
    //                  description='Calcula y asigna el siguiente número FDR al Case')
    // public static List<Output> generateFDRNumber(List<Input> inputs) {

    //     List<Output> results = new List<Output>();

    //     for (Input input : inputs) {

    //         Output out = new Output();

    //         //1. Bloquear el Case
    //         Case c = [
    //             SELECT Id, N_FDR__c
    //             FROM Case
    //             WHERE Id = :input.caseId
    //             LIMIT 1
    //             FOR UPDATE
    //         ];


    //           // VALIDACIÓN SI YA EXISTE ALGÚN PDF ADJUNTO AL CASO
    //             List<ContentDocumentLink> existingFdrFiles = [
    //                 SELECT Id,
    //                        ContentDocumentId,
    //                        ContentDocument.Title
    //                 FROM ContentDocumentLink
    //                 WHERE LinkedEntity.Id = :input.caseId AND ContentDocument.Title LIKE 'FDR Calidad - %'
    //             ];

    //                 // if (!existingFdrFiles.isEmpty()) {
    //                 //     throw new AuraHandledException(
    //                 //         '⚠ Ya existe un PDF FDR adjunto a este Caso. No es posible generar uno nuevo.'
    //                 //     );
    //                 // }

    //                 if (!existingFdrFiles.isEmpty()) {
    //                     out.alreadyExists = true;
    //                     results.add(out);
    //                     continue;
    //                 }

                    
                    

    //         //2. Si ya tiene número asignado, retornarlo sin generar uno nuevo
    //         // if (c.N_FDR__c != null) {
    //         //     out.generatedNumber = Integer.valueOf(c.N_FDR__c);
    //         //     results.add(out);
    //         //     continue;
    //         // }

    //         //3. Obtener el último correlativo global
    //         // AggregateResult maxResult = [
    //         //     SELECT MAX(N_FDR__c) maxNum
    //         //     FROM Case
    //         //     WHERE N_FDR__c != null
    //         // ];

    //         // Integer nextNumber = 1;

    //         // if (maxResult.get('maxNum') != null) {
    //         //     nextNumber = Integer.valueOf(maxResult.get('maxNum')) + 1;
    //         // }

    //         //4. Guardar número en el Case
    //         // c.N_FDR__c = nextNumber;
    //         // update c;

    //         //5. Retornar número generado
    //         // out.generatedNumber = nextNumber;
    //         // results.add(out);
    //     }

    //     return results;
    // }
}