// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'capability.dart';

class CapabilityMapper extends EnumMapper<Capability> {
  CapabilityMapper._();

  static CapabilityMapper? _instance;
  static CapabilityMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = CapabilityMapper._());
    }
    return _instance!;
  }

  static Capability fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  Capability decode(dynamic value) {
    switch (value) {
      case r'send':
        return Capability.send;
      case r'receive':
        return Capability.receive;
      case r'fs':
        return Capability.fs;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(Capability self) {
    switch (self) {
      case Capability.send:
        return r'send';
      case Capability.receive:
        return r'receive';
      case Capability.fs:
        return r'fs';
    }
  }
}

extension CapabilityMapperExtension on Capability {
  String toValue() {
    CapabilityMapper.ensureInitialized();
    return MapperContainer.globals.toValue<Capability>(this) as String;
  }
}

