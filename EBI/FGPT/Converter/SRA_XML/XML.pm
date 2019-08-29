#!/usr/bin/env perl
#
# SRA_XML/XML.pm - create SRA xml from magetab
#
# Anna Farne, European Bioinformatics Institute, 2009
#
# $Id: XML.pm 2384 2011-10-25 15:48:23Z farne $

package EBI::FGPT::Converter::SRA_XML::XML;
use Moose;
use MooseX::FollowPBP;
use XML::Parser;
use File::Spec;
use XML::Writer;
use Log::Log4perl qw(:easy);
use Data::Dumper;

Log::Log4perl->easy_init( { level => $INFO, layout => '%-5p - %m%n' } );

has 'magetab'     => ( is => 'rw', isa => 'Bio::MAGETAB' );
has 'reader'      => ( is => 'rw', isa => 'EBI::FGPT::Reader::MAGETAB' );
has 'output_file' => ( is => 'rw', isa => 'Str' );
has 'output_fh'   => ( is => 'rw', isa => 'FileHandle' );
has 'xml_writer'  =>
  ( is => 'rw', isa => 'XML::Writer', builder => '_build_xml_writer', lazy => 1, );
has 'datafiles' => ( is => 'rw', isa => 'ArrayRef', default => sub { [] } );
has 'accession' => ( is => 'rw', isa => 'Str' );
has 'center_name' =>
  ( is => 'rw', isa => 'Str', builder => '_populate_center_name', lazy => 1, );
has 'schema_type'       => ( is => 'rw', isa => 'Str' );
has 'schema_dir'        => ( is => 'rw', isa => 'Str', default => "." );
has 'extract_to_sample' => ( is => 'rw', isa => 'HashRef', default => sub { {} } );
has 'assay_to_extract'  => ( is => 'rw', isa => 'HashRef', default => sub { {} } );
has 'assay_to_fvs'      => ( is => 'rw', isa => 'HashRef', default => sub { {} } );

# A stop list used when mapping center names
my @stop_list = qw( the for of at );

# Some variables used by xml parser
my ( $in_element, $enum_type, @enum );

sub BUILD
{
	my $self = shift;

	my $path = $self->get_output_file;

	# Open output file for writing
	open( my $fh, ">", $path ) or die $!;
	$self->set_output_fh($fh);

	# Output xml declaration etc
	my $xml =
	  new XML::Writer( OUTPUT => $fh, DATA_MODE => 1, DATA_INDENT => 4, UNSAFE => 1 );
	$xml->xmlDecl('UTF-8');
	$self->set_xml_writer($xml);

}

sub _populate_center_name
{

	my $self = shift;

	# Attempt to find submitter affiliation or name to use
	my @contacts = $self->get_magetab->get_contacts;
	my $submitter_affil;
	my $submitter_found = 0;

	foreach my $contact (@contacts)
	{
		my @roles = $contact->get_roles;
		foreach my $role (@roles)
		{
			if ( $role && $role->get_value eq "submitter" )
			{
				$submitter_found = 1;
				$submitter_affil = $contact->get_organization;

				if ( !$submitter_affil )
				{
					LOGDIE "No submitter affiliation identified- center name cannot be added to xml";
				}
				return $submitter_affil;
			}
		}

	}

	# If after going through all the contacts we still have no submitter then die
	if ( $submitter_found == 0 )
	{
		LOGDIE "Submitter cannot be identified, center name cannot be added to xml";
	}
}

sub _build_xml_writer
{
	my $self = shift;
	my $xml = new XML::Writer(
							   OUTPUT      => $self->get_output_fh,
							   DATA_MODE   => 1,
							   DATA_INDENT => 4,
							   UNSAFE      => 1
	);
	$xml->xmlDecl('UTF-8');
	return $xml;
}

sub get_experiment
{
	my ($self) = @_;
	my $experiment;

	# Check an investigation exists
	if ( $self->get_magetab->has_investigations )
	{
		($experiment) = $self->get_magetab->get_investigations;
	}
	else { LOGDIE "No Experiment found"; }

	return $experiment;
}

sub get_assays
{
	my ($self) = @_;

	my @assay;

	# Check exists
	if ( $self->get_magetab->has_assays )
	{
		@assay = $self->get_magetab->get_assays;
	}

	else { LOGDIE "No Assays found"; }

	return @assay;
}

sub get_scans
{
	my ($self) = @_;

	my @scan;

	# Check exists
	if ( $self->get_magetab->has_dataAcquisitions )
	{
		@scan = $self->get_magetab->get_dataAcquisitions;
	}

	else { LOGDIE "No Scans/Data Acquisitions found"; }

	return @scan;
}

sub get_assay_from_name
{
	my ( $self, $name ) = @_;
	my $assay;
	my @assays = $self->get_assays;
	foreach my $as (@assays)
	{
		next unless $as->isa("Bio::MAGETAB::Assay");
		if ( $as->get_name eq $name )
		{
			$assay = $as;
			last;
		}
	}

	$assay or LOGDIE "Could not find Assay named $name";

	return $assay;
}

sub get_biomaterials
{
	my ($self) = @_;

	my @biomat;

	# Check exists
	if ( $self->get_magetab->has_sources )
	{
		@biomat = $self->get_magetab->get_sources;
	}
	else { LOGDIE "No source materials found"; }

	return @biomat;
}

sub get_comment
{

	#formerly called get_nvt
	my ( $self, $object, $name ) = @_;

	# Get all NVTs for object
	my @comments = @{ $object->get_comments() || [] };

	# Return the comment with the desired Name attribute
	foreach my $comment (@comments)
	{
		if ( $comment->get_name =~ /$name/i )
		{

			# Try to make value match enumerated list if one exists in schema
			my $value = $self->get_enum_value( $name, $comment->get_value );
			return $value;

		}
	}
	return undef;
}

sub get_enum_value
{
	my ( $self, $type, $value ) = @_;

	if ( my @enum = $self->get_enum_list($type) )
	{

		# Does value match enum list (case and space insensitive)?
		my ($match) = grep { lc($value) eq lc($_) } @enum;

		# If yes return enum value
		if ($match)
		{
			return $match;
		}
		else
		{
			WARN "No match found for $type \"$value\" in enumerated list:\n";
			return $value;
		}
	}
	else
	{

		# return orig value if no enum found
		return $value;
	}

}

sub get_enum_list
{
	my ( $self, $tmp_enum_type ) = @_;

	$enum_type  = $tmp_enum_type;
	$in_element = 0;
	@enum       = ();

	my $parser = XML::Parser->new(
								   Handlers => {
												 Start => \&_start,
												 End   => \&_end,
								   }
	);

	my $path = File::Spec->catfile( $self->get_schema_dir,
									"SRA." . $self->get_schema_type . ".xsd" );
	unless ( -r $path )
	{
		WARN "Cannot read schema file $path for checking enumerated list values\n";
		return @enum;
	}
	$parser->parsefile($path);
	return @enum;
}

# xml element start handler
sub _start
{
	my ( $expat, $type, %atts ) = @_;

	if ( $type eq "xs:element" and $in_element )
	{
		$in_element++;
	}
	if ( $type eq "xs:element" and $atts{name} eq $enum_type )
	{
		$in_element = 1;
	}
	if ( $type eq "xs:enumeration" and $in_element == 1 )
	{
		push @enum, $atts{value};
	}
}

# xml element end handler
sub _end
{
	my ( $expat, $type, %atts ) = @_;

	if ( $type eq "xs:element" and $in_element )
	{
		$in_element--;
	}
}

sub make_alias
{
	my ( $self, $name ) = @_;

	# Make a unique alias by concatenating accession to name
	my $alias = $self->get_accession . ":" . $name;

	return $alias;
}

sub get_protocol_text
{
	my ( $self, $object ) = @_;
	my $text;
	my $protocol_name;

	if ( $object->isa("Bio::MAGETAB::Sample") || $object->isa("Bio::MAGETAB::Source") )
	{
		my @outputEdges = $object->get_outputEdges;
		foreach my $outputEdge (@outputEdges)
		{
			my @protocolApplications = $outputEdge->get_protocolApplications;

			foreach my $protocolApplication (@protocolApplications)
			{

				my @protocols = $protocolApplication->get_protocol;
				foreach my $protocol (@protocols)
				{

					# Get text from all protocols used by object
					$text .= " " . $protocol->get_text;
				}

			}
			return $text;
		}
	}

# In the experiment xml we need to get the lib prep/extraction protocol associated with each extract
	if ( $object->isa("Bio::MAGETAB::Extract") )
	{
		my @inputEdges = $object->get_inputEdges;
		foreach my $inputEdge (@inputEdges)
		{
			my @protocolApplications = $inputEdge->get_protocolApplications;
			foreach my $protocolApplication (@protocolApplications)
			{

				my @protocols = $protocolApplication->get_protocol;
				foreach my $protocol (@protocols)
				{

					# Get text from all protocols used by object
					$text .= " " . $protocol->get_text;
				}

			}
			return $text;
		}

	}

	# For analysis xml we also need the protocol name
	if ( $object->isa("Bio::MAGETAB::Normalization") )
	{
		my @inputEdges = $object->get_inputEdges;
		foreach my $inputEdge (@inputEdges)
		{
			my @protocolApplications = $inputEdge->get_protocolApplications;
			foreach my $protocolApplication (@protocolApplications)
			{

				my @protocols = $protocolApplication->get_protocol;
				foreach my $protocol (@protocols)
				{

					# Get text from all protocols used by object
					$text          .= " " . $protocol->get_text;
					$protocol_name .= " " . $protocol->get_name;
				}

			}
			return ( $text, $protocol_name );
		}
	}

}

sub get_protocol_hardware
{
	my ( $self, $object ) = @_;

	# Get all hardware names from all protocols used by object
	my @protocols = $self->get_protocols($object);
	my $hardware;
	foreach my $prot (@protocols)
	{
		$hardware = $prot->get_hardware;
	}
	return $hardware;
}

sub get_protocols
{
	my ( $self, $object ) = @_;
	my @protocols;
	my @prot_apps;

	# Get protocol apps using the relevant get methods for the type of object
	if ( $object->isa("Bio::MAGETAB::Assay") )
	{
		my @inputEdges = $object->get_inputEdges;

		foreach my $inputEdge (@inputEdges)
		{
			@prot_apps = $inputEdge->get_protocolApplications;

			# Get all protocols used in these protocol apps
			foreach my $prot_app (@prot_apps)
			{
				push @protocols, $prot_app->get_protocol;
			}
		}

	}
	else
	{
		LOGDIE "No method for getting protocols from object type " . ref($object);
	}

	return @protocols;
}

sub get_performer
{
	my ( $self, $assay ) = @_;

	# Obtain protocol
	my @inputEdges = $assay->get_inputEdges
	  or LOGDIE "No Protocol application found for " . $assay->get_name . "\n";

	my %performers;
	foreach my $inputEdge (@inputEdges)
	{
		my @prot_app = $inputEdge->get_protocolApplications;
		foreach my $prot_app (@prot_app)
		{
			my @person = $prot_app->get_performers;

			foreach my $person (@person)
			{
				$performers{ $person->get_lastName } = 1;
			}
		}

	}

	my $string = join ",", keys %performers;
	return $string;
}

sub get_assay_from_file
{
	my ( $self, $file ) = @_;
	my $assay;

	INFO "Getting assay for " . $file->get_uri . "\n";

	# File input edge represents a protocol application whose node is an assay
	my @inputEdges = $file->get_inputEdges;

	if ($#inputEdges)
	{

		LOGDIE "More than one assay per " . $file->get_uri;
	}

	foreach my $inputEdge (@inputEdges)
	{
		$assay = $inputEdge->get_inputNode;
	}
	return $assay;
}

sub get_norm_from_file
{
	my ( $self, $file ) = @_;
	my $norm;

	INFO "Getting normalization name for " . $file->get_uri . "\n";

	# File input edge represents a protocol application whose node is an assay
	my @inputEdges = $file->get_inputEdges;

	if ($#inputEdges)
	{
		LOGDIE "More than one normalization name per " . $file->get_uri;
	}

	foreach my $inputEdge (@inputEdges)
	{
		$norm = $inputEdge->get_inputNode;
	}
	return $norm;
}

sub get_file_from_assay_name
{

	my ( $self, $assay_name ) = @_;

	my @file_list;
	my @all_assays = $self->get_assays;

	foreach my $assay (@all_assays)
	{

		# We only want the files associated with the assay we're working on
		if ( $assay->get_name eq $assay_name )
		{

			my @outputEdges = $assay->get_outputEdges;
			foreach my $outputEdge (@outputEdges)
			{
				my $file = $outputEdge->get_outputNode;

				#check its raw data
				my $data_type   = $file->get_dataType;
				my $data_format = $data_type->get_value;
				if (    ( $file->isa("Bio::MAGETAB::DataFile") )
					 && ( $data_format eq 'raw' ) )
				{
					push @file_list, $file;
				}

			}
		}

	}

	# return a list of data file objects
	return @file_list;
}

sub calculate_md5
{

	my ( $self, $file ) = @_;
	my $path      = $self->get_reader->get_data_file_path($file);
	my $file_name = $file->get_uri;
	my @comments  = $file->get_comments;

	$file_name =~ s/^file://g;

	# Check file exists - only if we are not skipping the data files
	unless ( $self->get_skip_data )
	{
		unless ( -e $path )
		{
			LOGDIE("File $file_name doesn't exist in unpacked dir");
		}
	}

	my $md5;
	my @md5;

	if ( $self->get_skip_data )
	{
		INFO("Skipping md5 calculation for $file_name");

		if (@comments)
		{
			foreach my $comment (@comments)
			{
				if ( $comment->get_name =~ /MD5/i )
				{
					$md5 = $comment->get_value;
					INFO("MD5 found in SDRF will be added to run xml");
				}

			}
		}
		else { INFO("No MD5 value found in SDRF"); }

	}
	else
	{
		if ( -r $path )
		{

			$md5 = `md5sum $path`;
			@md5 = split( / /, $md5 );
			$md5 = $md5[0];
		}
		else
		{
			LOGDIE("File $file not found or unreadable");
		}
		INFO("File: $file_name MD5: $md5");
	}
	return $md5;

}

sub close_xml
{
	my $self = shift;
	my $xml  = $self->get_xml_writer;
	$xml->endTag();
	$xml->end;
	close( $self->get_output_fh );
}

1;
