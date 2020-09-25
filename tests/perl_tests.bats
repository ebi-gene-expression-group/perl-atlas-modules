#!/usr/bin/env bats

setup() {
  atlasprodDir="atlasprod"
  export PERL5LIB=$PWD/tests/$atlasprodDir/perl_modules:$PERL5LIB
  export FASTQ_FILE_REPORT='http://ftp.ebi.ac.uk/pub/databases/ena/report/fastqFileReport.gz'
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