
=head1 NAME

Atlas::ExptFinder::Baseline.pm -- search ArrayExpress for differential Atlas candidates.

=head1 DESCRIPTION

This package extends Atlas::ExptFinder.pm to run checks specific to differential experiments.

=head1 SYNOPSIS

use Atlas::ExptFinder::Baseline;

# ...
my $searcher = Atlas::ExptFinder::Baseline->new;
$searcher->find_candidates( "Zea mays" );
$searcher->write_candidates_to_file( "Zea mays", "baseline" );

=head1 AUTHOR

Expression Atlas team <arrayexpress-atlas@ebi.ac.uk>

=cut

package Atlas::ExptFinder::Baseline;

use Moose;
use MooseX::FollowPBP;
use File::Spec;
use Log::Log4perl;
use EBI::FGPT::Reader::MAGETAB;
use EBI::FGPT::Config qw( $CONFIG );
use Atlas::ExptFinder::ArrayExpressAPI;

extends 'Atlas::ExptFinder';

has 'analysis_type' => (
	is		=> 'ro',
	isa		=> 'Str',
	default	=> 'baseline'
);

has 'efcount' => (
    is  => 'rw',
    isa => 'Int',
    default => 1
);

has 'exptype' => (
    is  => 'rw',
    isa => 'Str',
    default => 'RNA-seq'
);

my $logger = Log::Log4perl::get_logger;

sub remove_ineligible_experiments {
	
	my ( $self ) = @_;

	foreach my $expAcc ( keys %{ $self->get_candidates_hash } ) {

		my $aeAPI = Atlas::ExptFinder::ArrayExpressAPI->new;

		my $numFactorValues = $aeAPI->get_num_factor_values( $expAcc );
	
		# Minimum number of factor values.
		my $minimum = 3;

		# If number of factor values is less than minimum, remove it from
		# candidates.
		if( $numFactorValues < $minimum ) {

			$logger->info(
				"$expAcc has fewer than $minimum factor values so is not eligible for baseline Atlas."
			);

			$self->remove_from_candidates( $expAcc );
		}
	}
	
	my $numExps = keys %{ $self->get_candidates_hash };

	$logger->info(
		"$numExps experiments have passed Baseline eligibility checking."
	);
}

1;
