#!/usr/bin/env bats


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

@test "[magetab-curation-scripts] Run validate_magetab.pl (corrected MAGE-TAB)" {
  if [ -z ${PERL5LIB+x} ]; then
    skip "PERL5LIB not defined"
  fi

  run sed -i "s/atlas_property_types:/atlas_property_types:\n    - isolate/" $CONDA_PREFIX/atlasprod/supporting_files/ae_atlas_controlled_vocabulary.yml && sed -i "s/arrayexpress_experiment_types:/arrayexpress_experiment_types:\n    - DNA-seq/" $CONDA_PREFIX/atlasprod/supporting_files/ae_atlas_controlled_vocabulary.yml && validate_magetab.pl -i $PWD/tests/E-MTAB-9898/E-MTAB-9898.idf.txt -c 
  echo "output = ${output}"
  [ "$status" -eq 0 ]
}
