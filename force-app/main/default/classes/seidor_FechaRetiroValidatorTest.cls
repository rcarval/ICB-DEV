@IsTest
private class seidor_FechaRetiroValidatorTest {

    /**
     * Crea un Case de prueba.
     */
    private static Case crearCaso(Date fechaRetiro) {

        return new Case(
            Subject = 'Caso de prueba',
            Origin = 'Phone',
            Status = 'New',
            Fecha_retiro__c = fechaRetiro
        );
    }

    /**
     * Retorna una fecha restando N días hábiles
     * considerando hábiles de lunes a sábado.
     */
    private static Date restarDiasHabiles(Date fechaBase, Integer diasHabiles){

        Date fecha = fechaBase;
        Integer contador = 0;

        while(contador < diasHabiles){

            fecha = fecha.addDays(-1);

            Integer diaSemana = Integer.valueOf(
                DateTime.newInstance(
                    fecha.year(),
                    fecha.month(),
                    fecha.day()
                ).format('u')
            );

            // Domingo = 7
            if(diaSemana != 7){
                contador++;
            }
        }

        return fecha;
    }

    @IsTest
    static void insertarFechaHoy(){

        Case c = crearCaso(Date.today());

        Test.startTest();
        insert c;
        Test.stopTest();

        System.assertNotEquals(null, c.Id);
    }

    @IsTest
    static void insertarFechaFutura(){

        Case c = crearCaso(Date.today().addDays(5));

        Test.startTest();
        insert c;
        Test.stopTest();

        System.assertNotEquals(null, c.Id);
    }

    @IsTest
    static void insertarFechaValida8DiasHabiles(){

        Case c = crearCaso(restarDiasHabiles(Date.today(), 8));

        Test.startTest();
        insert c;
        Test.stopTest();

        System.assertNotEquals(null, c.Id);
    }

    @IsTest
    static void insertarFechaInvalida9DiasHabiles(){

        Case c = crearCaso(restarDiasHabiles(Date.today(), 9));

        Test.startTest();

        try{
            insert c;
            System.assert(false,
                'Debió producirse un error de validación.');
        }
        catch(DmlException ex){

            System.assert(
                ex.getDmlMessage(0).contains('8 días hábiles'),
                ex.getMessage()
            );
        }

        Test.stopTest();
    }

    @IsTest
    static void actualizarSinCambiarFecha(){

        Case c = crearCaso(Date.today());

        insert c;

        c.Subject = 'Cambio de Subject';

        Test.startTest();
        update c;
        Test.stopTest();

        System.assertEquals('Cambio de Subject', c.Subject);
    }

    @IsTest
    static void actualizarFechaInvalida(){

        Case c = crearCaso(Date.today());

        insert c;

        c.Fecha_retiro__c = restarDiasHabiles(Date.today(), 9);

        Test.startTest();

        try{

            update c;

            System.assert(false,
                'Debió lanzar error de validación.');

        }catch(DmlException ex){

            System.assert(
                ex.getDmlMessage(0).contains('8 días hábiles'),
                ex.getMessage()
            );

        }

        Test.stopTest();

    }
}