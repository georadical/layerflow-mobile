import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/core/address/address_normalizer.dart';
import 'package:layerflow_capture/data/repositories/r1_directory_repository.dart';

void main() {
  group('pinned algorithm — the spec\'s own examples', () {
    test('K 2 4A 09 → CARRERA 2 # 4A-09', () {
      expect(normalizeAddress('K 2 4A 09').direccionNorm, 'CARRERA 2 # 4A-09');
    });

    test('CL 5 Nº 2-06 → CALLE 5 # 2-06 (the º decomposes, NO is dropped)', () {
      expect(normalizeAddress('CL 5 Nº 2-06').direccionNorm, 'CALLE 5 # 2-06');
    });

    test('SAMARIA → not a street address (rural name)', () {
      expect(normalizeAddress('SAMARIA').direccionNorm, isNull);
    });
  });

  group('number markers — pinned v1.1 reference cases (backend 8b0502d)', () {
    test('NRO always dropped', () {
      expect(
          normalizeAddress('K 2 NRO 4A 09').direccionNorm, 'CARRERA 2 # 4A-09');
    });

    test('N° (degree sign) leaves a bare N that is dropped before a digit', () {
      expect(normalizeAddress('C 4 N° 3 15').direccionNorm, 'CALLE 4 # 3-15');
    });

    test('final bare N is the cardinal suffix — never eaten', () {
      final n = normalizeAddress('CALLE 5 N');
      expect(n.direccionNorm, isNull);
      expect(n.barrio, 'N', reason: 'trailing alpha goes to barrio');
    });
  });

  group('pinned algorithm — structure', () {
    test('clean strips accents, symbols and collapses whitespace', () {
      expect(cleanAddress('  cÁlle   5 #2-06, '), 'CALLE 5 2 06');
    });

    test('via synonyms map (first token only)', () {
      expect(
          normalizeAddress('CRA 7 12 30').direccionNorm, 'CARRERA 7 # 12-30');
      expect(
          normalizeAddress('TV 3 4 05').direccionNorm, 'TRANSVERSAL 3 # 4-05');
      // A via word NOT in first position does not trigger.
      expect(normalizeAddress('BARRIO CALLE 5').direccionNorm, isNull);
    });

    test('structural suffixes extract from any position', () {
      final n = normalizeAddress('C 5 IN 2 06 LO 4 MZ B');
      expect(n.direccionNorm, 'CALLE 5 # 2-06');
      expect(n.interior, isTrue);
      expect(n.lote, '4');
      expect(n.mz, 'B');
    });

    test('trailing pure-alpha tokens become the barrio, in order', () {
      final n = normalizeAddress('C 5 2 06 SAN JOSE');
      expect(n.direccionNorm, 'CALLE 5 # 2-06');
      expect(n.barrio, 'SAN JOSE');
    });

    test('incomplete core (fewer than 3 parts) yields no direccion_norm', () {
      expect(normalizeAddress('C 5 2').direccionNorm, isNull);
    });
  });

  group('typeahead prefix (progressive, gated — CL-R1 v1.1)', () {
    test('the specificity gate: nothing before via + número + cruce', () {
      // One letter, one tap, placa "c": the laziness the gate kills.
      expect(R1DirectoryRepository.typeaheadPrefix('C'), isNull);
      expect(R1DirectoryRepository.typeaheadPrefix('C 5'), isNull);
    });

    test('grows from the gate onward', () {
      expect(R1DirectoryRepository.typeaheadPrefix('C 5 2'), 'CALLE 5 # 2');
      expect(R1DirectoryRepository.typeaheadPrefix('C 5 2 0'), 'CALLE 5 # 2-0');
    });

    test('rural text yields no prefix — no fake coverage', () {
      expect(R1DirectoryRepository.typeaheadPrefix('CASA MEJORA'), isNull);
      expect(R1DirectoryRepository.typeaheadPrefix(''), isNull);
    });
  });

  group('placa mode + part match (CL-R1 v1.2, backend a52883d)', () {
    test('placaPartPattern: auto-detected, gated at cruce + start of placa',
        () {
      expect(R1DirectoryRepository.placaPartPattern('3A 08'), '# 3A-08');
      expect(R1DirectoryRepository.placaPartPattern('3A 0'), '# 3A-0');
      expect(R1DirectoryRepository.placaPartPattern('3'), isNull,
          reason: 'the gate, placa-mode flavour');
      expect(R1DirectoryRepository.placaPartPattern('C 13 3A'), isNull,
          reason: 'a via first token belongs to address mode');
      expect(R1DirectoryRepository.placaPartPattern(''), isNull);
    });

    test('typedMatchesLinked: full match and cruce-placa part match', () {
      const linked = 'CALLE 13 # 3A-08';
      expect(typedMatchesLinked('C 13 3A 08', linked), isTrue);
      expect(typedMatchesLinked('3A 08', linked), isTrue,
          reason: 'the door plate usually shows only that part');
      expect(typedMatchesLinked('3A-08', linked), isTrue);
      expect(typedMatchesLinked('3A 09', linked), isFalse);
      expect(typedMatchesLinked('c', linked), isFalse);
      expect(typedMatchesLinked('', linked), isFalse);
    });
  });

  group('edit distance (OCR soft-check, CL-R2)', () {
    test('zero for equal, symmetric-ish sanity', () {
      expect(editDistance('CALLE 5 2 06', 'CALLE 5 2 06'), 0);
      expect(editDistance('CALLE 5 2 06', 'CALLE 5 2 08'), 1);
      expect(editDistance('', 'ABC'), 3);
    });
  });
}
