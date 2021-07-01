#!/usr/bin/env bats

setup() {
    vocab_filename=ae_atlas_controlled_vocabulary.yml
    vocab_file="$PWD/supporting_files/${vocab_filename}" 
    corrected_vocab_file="$PWD/$vocab_filename" 
    vocab_sed_command="sed 's/atlas_property_types:/atlas_property_types:\n    - isolate/' ${vocab_file}.default > ${corrected_vocab_file} && sed -i 's/atlas_experiment_types:/atlas_experiment_types:\n    - DNA-seq/' ${corrected_vocab_file} && sed -i 's/arrayexpress_experiment_types:/arrayexpress_experiment_types:\n    - DNA-seq/' ${corrected_vocab_file}"
    corrected_validate_command="env ATLAS_META_CONFIG=$PWD validate_magetab.pl -i $PWD/tests/E-MTAB-9898/E-MTAB-9898.idf.txt -c"
}

@test "Check that perl is in the path" {
    run which perl
    [ "$status" -eq 0 ]
}

@test "Check [geo import] main scripts in the path" {
    run which import_geo_subs.pl
    [ "$status" -eq 0 ]
}

@test "Check [geo import] magetab convertor in the path" {
    run which new_soft2magetab.pl
    [ "$status" -eq 0 ]
}

@test "[geo-import] Import microarray study" {
  if [ -z ${PERL5LIB+x} ]; then
    skip "PERL5LIB not defined"
  fi
  run import_geo_subs.pl -x -f $PWD/tests/microarray_geo.txt -o $BATS_TMPDIR
  echo "output = ${output}"
  [ "$status" -eq 0 ]
}

@test "[geo-import] Import RNA-seq study" {
  if [ -z ${PERL5LIB+x} ]; then
    skip "PERL5LIB not defined"
  fi
  run import_geo_subs.pl -x -f $PWD/tests/rnaseq_geo.txt -o $BATS_TMPDIR
  echo "output = ${output}"
  [ "$status" -eq 0 ]
}

@test "[geo-import] Import scRNA-seq study" {
  if [ -z ${PERL5LIB+x} ]; then
    skip "PERL5LIB not defined"
  fi
  run import_geo_subs.pl -x -f $PWD/tests/scrnaseq_geo.txt -o $BATS_TMPDIR
  echo "output = ${output}"
  [ "$status" -eq 0 ]
}

@test "[magetab-curation-scripts] Run validate_magetab.pl" {
  if [ -z ${PERL5LIB+x} ]; then
    skip "PERL5LIB not defined"
  fi

  run validate_magetab.pl -i $PWD/tests/E-MTAB-9898/E-MTAB-9898.idf.txt -c 
  echo "output = ${output}"
  [ "$status" -eq 1 ]
}

@test "Correct vocab YML" {
  if [ -z ${PERL5LIB+x} ]; then
    skip "PERL5LIB not defined"
  fi

  run eval "$vocab_sed_command"
  echo -e "Command: $vocab_sed_command\noutput = ${output}"
  [ "$status" -eq 0 ]
}

@test "[magetab-curation-scripts] Run check_atlas_eligibility.pl" {
  if [ -z ${PERL5LIB+x} ]; then
    skip "PERL5LIB not defined"
  fi

  run env ATLAS_META_CONFIG=$PWD check_atlas_eligibility.pl -i $PWD/tests/E-MTAB-9898/E-MTAB-9898.idf.txt
  echo -e "output = ${output}"
  [ "$status" -eq 0 ]
}

@test "[magetab-curation-scripts] Run validate_magetab.pl (corrected MAGE-TAB)" {
  if [ -z ${PERL5LIB+x} ]; then
    skip "PERL5LIB not defined"
  fi

  run eval "$corrected_validate_command"
  echo -e "Command: $corrected_validate_command\noutput = ${output}"
  [ "$status" -eq 0 ]
}

@test "[atlas-experiment-metadata] Run condense_sdrf.pl" {

  run condense_sdrf.pl -z -x $PWD/config/zooma_exclusions.yml -e E-MTAB-9898 -fi $PWD/tests/E-MTAB-9898/E-MTAB-9898.idf.txt -o $PWD
  echo "output = ${output}"
  [ "$status" -eq 0 ]
}
