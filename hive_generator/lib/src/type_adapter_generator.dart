import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:hive/hive.dart';
import 'package:hive_generator/src/builder.dart';
import 'package:hive_generator/src/class_builder.dart';
import 'package:hive_generator/src/enum_builder.dart';
import 'package:hive_generator/src/helper.dart';
import 'package:source_gen/source_gen.dart';

class TypeAdapterGenerator extends GeneratorForAnnotation<HiveType> {
  static String generateName(String typeName) {
    var adapterName = '${typeName}Adapter'.replaceAll(
      RegExp(r'[^A-Za-z0-9]+'),
      '',
    );
    if (adapterName.startsWith('_')) adapterName = adapterName.substring(1);
    if (adapterName.startsWith(r'$')) adapterName = adapterName.substring(1);
    return adapterName;
  }

  @override
  dynamic generateForAnnotatedElement(
    covariant Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) {
    final interface = getInterface(element);

    final gettersAndSetters = getAccessors(interface, element.library!);
    final getters = gettersAndSetters[0];
    final setters = gettersAndSetters[1];

    verifyFieldIndices(getters);
    verifyFieldIndices(setters);

    final typeId = getTypeId(annotation);
    final adapterName = getAdapterName(interface.name, annotation);

    final builder =
        interface is EnumElement
            ? EnumBuilder(interface, getters)
            : ClassBuilder(interface, getters, setters);

    return '''
class $adapterName extends TypeAdapter<${interface.name}> {
  @override
  final int typeId = $typeId;

  @override
  ${interface.name} read(BinaryReader reader) {
    ${builder.buildRead()}
  }

  @override
  void write(BinaryWriter writer, ${interface.name} obj) {
    ${builder.buildWrite()}
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is $adapterName &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
''';
  }

  InterfaceElement getInterface(Element element) {
    check(
      element.kind == ElementKind.CLASS || element.kind == ElementKind.ENUM,
      'Only classes or enums are allowed to be annotated with @HiveType.',
    );
    return element as InterfaceElement;
  }

  Set<String> getAllAccessorNames(InterfaceElement interface) {
    final accessorNames = <String>{};
    final supertypes = interface.allSupertypes.map((t) => t.element);

    for (final type in [interface, ...supertypes]) {
      for (final accessor in type.accessors) {
        if (accessor.isSetter) {
          accessorNames.add(
            accessor.name.substring(0, accessor.name.length - 1),
          );
        } else {
          accessorNames.add(accessor.name);
        }
      }
    }
    return accessorNames;
  }

  List<List<AdapterField>> getAccessors(
    InterfaceElement interface,
    LibraryElement library,
  ) {
    final accessorNames = getAllAccessorNames(interface);

    final getters = <AdapterField>[];
    final setters = <AdapterField>[];

    for (final name in accessorNames) {
      final getter = interface.lookUpGetter(name, library);
      if (getter != null) {
        final getterAnn = getHiveFieldAnn(getter);
        if (getterAnn != null) {
          getters.add(
            AdapterField(
              getterAnn.index,
              getter.name,
              getter.returnType,
              getterAnn.defaultValue,
            ),
          );
        }
      }

      final setter = interface.lookUpSetter('$name=', library);
      if (setter != null) {
        final fieldElement = setter;
        final setterAnn = getHiveFieldAnn(fieldElement);
        if (setterAnn != null) {
          setters.add(
            AdapterField(
              setterAnn.index,
              fieldElement.name,
              fieldElement.returnType,
              setterAnn.defaultValue,
            ),
          );
        }
      }
    }

    return [getters, setters];
  }

  void verifyFieldIndices(List<AdapterField> fields) {
    for (final field in fields) {
      check(
        field.index >= 0 && field.index <= 255,
        'Field numbers can only be in the range 0-255.',
      );
      for (final otherField in fields) {
        if (otherField == field) continue;
        if (otherField.index == field.index) {
          throw HiveError(
            'Duplicate field number: ${field.index}. Fields "${field.name}" '
            'and "${otherField.name}" have the same number.',
          );
        }
      }
    }
  }

  String getAdapterName(String typeName, ConstantReader annotation) {
    final annAdapterName = annotation.read('adapterName');
    if (annAdapterName.isNull) {
      return generateName(typeName);
    } else {
      return annAdapterName.stringValue;
    }
  }

  int getTypeId(ConstantReader annotation) {
    check(
      !annotation.read('typeId').isNull,
      'You have to provide a non-null typeId.',
    );
    return annotation.read('typeId').intValue;
  }
}
