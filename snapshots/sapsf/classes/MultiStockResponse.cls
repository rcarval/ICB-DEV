/**
 * @description       :
 * @author            : JM
 * @group             :
 * @last modified on  : 24-09-2021
 * @last modified by  : JM
 **/
public inherited sharing class MultiStockResponse {
    public class Databases {
        public Database Database { get; set; }

        public Databases(JSONParser parser) {
            while (parser.nextToken() != System.JSONToken.END_OBJECT) {
                if (parser.getCurrentToken() == System.JSONToken.FIELD_NAME) {
                    String text = parser.getText();
                    if (parser.nextToken() != System.JSONToken.VALUE_NULL) {
                        if (text == 'Database') {
                            Database = new Database(parser);
                        } else {
                            System.debug(
                                LoggingLevel.WARN,
                                'Databases consuming unrecognized property: ' +
                                text
                            );
                            consumeObject(parser);
                        }
                    }
                }
            }
        }
    }

    public class Database {
        public String Company { get; set; }
        public List<Stock> Stock { get; set; }

        public Database(JSONParser parser) {
            while (parser.nextToken() != System.JSONToken.END_OBJECT) {
                if (parser.getCurrentToken() == System.JSONToken.FIELD_NAME) {
                    String text = parser.getText();
                    if (parser.nextToken() != System.JSONToken.VALUE_NULL) {
                        if (text == 'Company') {
                            Company = parser.getText();
                        } else if (text == 'Stock') {
                            Stock = arrayOfStock(parser);
                        } else {
                            System.debug(
                                LoggingLevel.WARN,
                                'Database consuming unrecognized property: ' +
                                text
                            );
                            consumeObject(parser);
                        }
                    }
                }
            }
        }
    }

    public List<Databases> Databases { get; set; }

    public MultistockResponse(JSONParser parser) {
        while (parser.nextToken() != System.JSONToken.END_OBJECT) {
            if (parser.getCurrentToken() == System.JSONToken.FIELD_NAME) {
                String text = parser.getText();
                if (parser.nextToken() != System.JSONToken.VALUE_NULL) {
                    if (text == 'Databases') {
                        Databases = arrayOfDatabases(parser);
                    } else {
                        System.debug(
                            LoggingLevel.WARN,
                            'MultistockResponse consuming unrecognized property: ' +
                            text
                        );
                        consumeObject(parser);
                    }
                }
            }
        }
    }

    public class Stock {
        public String WhsCode { get; set; }
        public String OnHand { get; set; }
        public String IsCommited { get; set; }
        public String OnOrder { get; set; }
        public String sapDatabase {get; set;}

        public Stock(JSONParser parser) {
            while (parser.nextToken() != System.JSONToken.END_OBJECT) {
                if (parser.getCurrentToken() == System.JSONToken.FIELD_NAME) {
                    String text = parser.getText();
                    if (parser.nextToken() != System.JSONToken.VALUE_NULL) {
                        if (text == 'WhsCode') {
                            WhsCode = parser.getText();
                        } else if (text == 'OnHand') {
                            OnHand = parser.getText();
                        } else if (text == 'IsCommited') {
                            IsCommited = parser.getText();
                        } else if (text == 'OnOrder') {
                            OnOrder = parser.getText();
                        }
                        else if (text == 'sapDatabase') {
                            sapDatabase = parser.getText();
                        } else {
                            System.debug(
                                LoggingLevel.WARN,
                                'Stock consuming unrecognized property: ' + text
                            );
                            consumeObject(parser);
                        }
                    }
                }
            }
        }
    }

    public static MultistockResponse parse(String json) {
        System.JSONParser parser = System.JSON.createParser(json);
        return new MultistockResponse(parser);
    }

    public static void consumeObject(System.JSONParser parser) {
        Integer depth = 0;
        do {
            System.JSONToken curr = parser.getCurrentToken();
            if (
                curr == System.JSONToken.START_OBJECT ||
                curr == System.JSONToken.START_ARRAY
            ) {
                depth++;
            } else if (
                curr == System.JSONToken.END_OBJECT ||
                curr == System.JSONToken.END_ARRAY
            ) {
                depth--;
            }
        } while (depth > 0 && parser.nextToken() != null);
    }

    private static List<Databases> arrayOfDatabases(System.JSONParser p) {
        List<Databases> res = new List<Databases>();
        if (p.getCurrentToken() == null)
            p.nextToken();
        while (p.nextToken() != System.JSONToken.END_ARRAY) {
            res.add(new Databases(p));
        }
        return res;
    }

    private static List<Stock> arrayOfStock(System.JSONParser p) {
        List<Stock> res = new List<Stock>();
        if (p.getCurrentToken() == null)
            p.nextToken();
        while (p.nextToken() != System.JSONToken.END_ARRAY) {
            res.add(new Stock(p));
        }
        return res;
    }
}