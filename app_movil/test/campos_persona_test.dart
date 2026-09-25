import 'package:essence_movil/widgets/campos_persona.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Validaciones del registro y la ficha de cliente', () {
    test('nombre completo obligatorio, con apellido', () {
      expect(validarNombre(''), isNotNull);
      expect(validarNombre('Ana'), isNotNull);
      expect(validarNombre('Ana Gómez'), isNull);
    });

    test('celular: solo números, 10 dígitos, empieza por 3', () {
      expect(validarCelular(''), isNotNull);
      expect(validarCelular('300123456'), isNotNull); // 9 dígitos
      expect(validarCelular('6041234567'), isNotNull); // fijo
      expect(validarCelular('300-123-45'), isNotNull);
      expect(validarCelular('3001234567'), isNull);
    });

    test('documento según el tipo', () {
      expect(validarDocumento('CC', ''), isNotNull);
      expect(validarDocumento('CC', '12AB34'), isNotNull);
      expect(validarDocumento('CC', '1037654321'), isNull);
      expect(validarDocumento('NIT', '900123456-7'), isNull);
      expect(validarDocumento('PAS', 'AB123456'), isNull);
    });

    test('correo obligatorio solo en el registro', () {
      expect(validarCorreo('', obligatorio: true), isNotNull);
      expect(validarCorreo('', obligatorio: false), isNull);
      expect(validarCorreo('ana@correo', obligatorio: false), isNotNull);
      expect(validarCorreo('ana@correo.com', obligatorio: true), isNull);
    });

    test('hay 6 tipos de documento', () {
      expect(tiposDocumento.keys, containsAll(['CC', 'TI', 'CE', 'PPT', 'PAS', 'NIT']));
    });
  });
}
