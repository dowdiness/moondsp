///|
using @identity {
  type DefinitionId,
  type ReferenceBindingId,
  type ReferenceId,
  type SourceAtomId,
  type SourceEpoch,
}

///|
const SOURCE_IDENTITY_MAX_TEST : Int64 = 9007199254740991L

///|
fn assert_invalid_source_identity(value : Int64) -> Unit {
  try SourceEpoch::SourceEpoch(value) catch {
    StableIdError::InvalidId(_) => ()
    _ => abort("expected InvalidId")
  } noraise {
    _ => abort("expected InvalidId")
  }
}

///|
test "source identity constructors enforce positive JavaScript-safe values" {
  assert_invalid_source_identity(-1L)
  assert_invalid_source_identity(0L)
  assert_invalid_source_identity(SOURCE_IDENTITY_MAX_TEST + 1L)
  let epoch = SourceEpoch::SourceEpoch(SOURCE_IDENTITY_MAX_TEST)
  let atom = SourceAtomId::SourceAtomId(epoch, SOURCE_IDENTITY_MAX_TEST)
  @debug.assert_eq(epoch.serial(), SOURCE_IDENTITY_MAX_TEST)
  @debug.assert_eq(atom.epoch(), epoch)
  @debug.assert_eq(atom.serial(), SOURCE_IDENTITY_MAX_TEST)
}

///|
test "source identity IDs compare epoch and serial" {
  let first_epoch = SourceEpoch::SourceEpoch(1L)
  let second_epoch = SourceEpoch::SourceEpoch(2L)
  let atom = SourceAtomId::SourceAtomId(first_epoch, 1L)
  assert_true(atom == SourceAtomId::SourceAtomId(first_epoch, 1L))
  assert_true(atom != SourceAtomId::SourceAtomId(second_epoch, 1L))
  assert_true(atom != SourceAtomId::SourceAtomId(first_epoch, 2L))

  let definition = DefinitionId::DefinitionId(first_epoch, 1L)
  let reference = ReferenceId::ReferenceId(first_epoch, 1L)
  let binding = ReferenceBindingId::ReferenceBindingId(first_epoch, 1L)
  assert_true(definition == DefinitionId::DefinitionId(first_epoch, 1L))
  assert_true(reference == ReferenceId::ReferenceId(first_epoch, 1L))
  assert_true(
    binding == ReferenceBindingId::ReferenceBindingId(first_epoch, 1L),
  )
  @debug.assert_eq(definition.epoch(), first_epoch)
  @debug.assert_eq(reference.serial(), 1L)
  @debug.assert_eq(binding.serial(), 1L)
}
