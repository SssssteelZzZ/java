import java.util.Scanner;

public class StringCalculate {
    public static void main(String[] args) throws Exception {
        Scanner scanner = new Scanner(System.in);
        System.out.println("Введите текст:");
        String sc = scanner.nextLine().trim();
        char operation;
        String[] operands;

        if (sc.contains(" + ")) {
            operands = sc.split(" \\+ ");
            operation = '+';
        } else if (sc.contains(" - ")) {
            operands = sc.split(" - ");
            operation = '-';
        } else if (sc.contains(" * ")) {
            operands = sc.split(" \\* ");
            operation = '*';
        } else if (sc.contains(" / ")) {
            operands = sc.split(" / ");
            operation = '/';
        } else {
            throw new Exception("Некорректная операция.");
        }

        for (int i = 0; i < operands.length; i++) {
            operands[i] = operands[i].replace("\"", "").trim();
        }

        if (operands[0].length() > 10) {
            throw new Exception("Длина строки не должна превышать 10 символов.");
        }

        String result;


        switch (operation) {
            case '+':
                if (operands[1].length() > 10) {
                    throw new Exception("Длина строки не должна превышать 10 символов.");
                }
                result = operands[0] + operands[1];
                break;
            case '-':
                result = operands[0].replaceFirst(operands[1], "");
                break;
            case '*':
                int multiplier = Integer.parseInt(operands[1]);
                if (multiplier < 1 || multiplier > 10) {
                    throw new Exception("Число должно быть от 1 до 10.");
                }
                StringBuilder sb = new StringBuilder();
                for (int i = 0; i < multiplier; i++) {
                    sb.append(operands[0]);
                }
                result = sb.toString();
                break;
            case '/':
                int divisor = Integer.parseInt(operands[1]);
                if (divisor < 1 || divisor > 10) {
                    throw new Exception("Число должно быть от 1 до 10.");
                }
                int partLength = operands[0].length() / divisor;
                result = operands[0].substring(0, partLength);
                break;
            default:
                throw new Exception("Некорректная операция.");
        }

        if (result.length() > 40) {
            result = result.substring(0, 40) + "...";
            System.out.println(result);
        }

        System.out.println("\"" + result + "\"");
    }

    public static boolean Numb(String str) {
        return str.matches("\\d+");
    }
}