/**
 * @Name        : icbfs_RutValidator
 * @Author      : Jose Illanes
 * @CreatedDate : 2026-01-26
 * @Description : Utilidad para validar RUT chileno (formato + dígito verificador).
 * @Notes       : Formato esperado xxxxxxxx-x o xxxxxxxx-K (sin puntos).
 */
public with sharing class icbfs_RutValidator {

    private static final Pattern RUT_PATTERN = Pattern.compile('^[0-9]{7,8}-[0-9Kk]{1}$');

    
    public class Result {
        public Boolean isValid;
        public Boolean isFormatOk;

        public Result(Boolean isFormatOk, Boolean isValid) {
            this.isFormatOk = isFormatOk;
            this.isValid = isValid;
        }
    }

    public static Result validate(String rutRaw) {
        if (String.isBlank(rutRaw)) {
            return new Result(true, true);
        }

        String rut = rutRaw.trim();

        
        if (!RUT_PATTERN.matcher(rut).matches()) {
            return new Result(false, false);
        }

        
        List<String> parts = rut.split('-');
        if (parts.size() != 2) {
            return new Result(false, false);
        }

        Integer cuerpo;
        try {
            cuerpo = Integer.valueOf(parts[0]);
        } catch (Exception ex) {
            return new Result(false, false);
        }

        String dvIngresado = parts[1].toUpperCase();
        String dvEsperado = calcularDV(cuerpo);

        return new Result(true, dvEsperado == dvIngresado);
    }

    // Sobrecarga para escenarios donde la validación depende de LeadSource.
    // Si LeadSource es "OpenDay", se omite la validación de RUT.
    public static Result validate(String rutRaw, String leadSource) {
        if (leadSource != null && leadSource.equalsIgnoreCase('OpenDay')) {
            return new Result(true, true);
        }
        return validate(rutRaw);
    }

    private static String calcularDV(Integer cuerpo) {
        Integer sum = 0;
        Integer mul = 2;

        Integer n = cuerpo;
        while (n > 0) {
            Integer dig = Math.mod(n, 10);
            sum += dig * mul;
            mul = (mul == 7) ? 2 : (mul + 1);
            n = n / 10;
        }

        Integer res = 11 - Math.mod(sum, 11);

        if (res == 11) return '0';
        if (res == 10) return 'K';
        return String.valueOf(res);
    }
}