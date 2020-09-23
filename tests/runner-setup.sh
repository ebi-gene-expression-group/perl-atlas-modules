#!/bin/bash

DIR=$(dirname ${BASH_SOURCE[0]})
export PATH=$DIR/../tests:$DIR/../supporting_files:$PATH
export PERL5LIB=$DIR/../perl_modules:$PERL5LIB
