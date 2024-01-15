# $Id$
# jn, 12.04.07

package ZBW::Logutil;

use strict;
use warnings;

use Log::Log4perl qw(:no_extra_logdie_message);
use Log::Log4perl::Level;

our $VERSION = "0.24";

my $log = Log::Log4perl->get_logger('ZBW::Logutil');
$log->level('DEBUG');

=head1 NAME

ZBW::Logutil - encapsulates Log4perl with default settings


=head1 SYNOPSIS

  use ZBW::Logutil;
  my $log = ZBW::Logutil->get_logger('xyz.log.conf');
  my $log = ZBW::Logutil->get_logger(); # default logger

=head1 DESCRIPTION



=cut

############################
#####  PUBLIC METHODS  #####
############################

=head2 Class Methods

=over 2

=item get_logger ($log_conf)

=item get_logger ()

Returns a Log4perl instance initialized with file $log_conf 
or a default configuration.

SIG warn and SIG die are redirected to Log4perl. Duplicate 
die messages are suppressed.

=cut

sub get_logger {
  my $class    = shift;
  my $log_conf = shift;

  # Log configuration
  if ($log_conf) {
    if ( -f $log_conf ) {
      Log::Log4perl->init($log_conf);
    } else {
      die "FATAL: kann Log-Konfiguration $log_conf nicht finden\n";
    }
  } else {
    my $conf = __PACKAGE__->get_default_conf();
    Log::Log4perl->init( \$conf );
  }

  my $log = Log::Log4perl->get_logger();

  # Catch signals
  $SIG{__DIE__} = sub {
    if ($^S) {
      ## We're in an eval {} and don't want log
      ## this message but catch it later
      return;
    }
    ${Log::Log4perl::caller_depth}++;
    $log->logconfess(@_);
  };
  $SIG{__WARN__} = sub {
    if ($^S) {
      ## We're in an eval {} and don't want log
      ## this message but catch it later
      return;
    }
    ${Log::Log4perl::caller_depth}++;
    $log->logcluck(@_);
  };

  return $log;
}

=item get_default_conf

Returns a default configuration (Level INFO, no log file, no
mail).

=cut

sub get_default_conf {

  my $class = shift;

  my $LOG_CONF = <<'EOF';
############################################################
# A simple root logger 
############################################################

layout_pattern = %d %p %m%n

log4perl.logger = INFO, Screen

log4perl.filter.doit_filter = sub { $main::doit }

###############################################################################
########### log to console ####################################################
###############################################################################
log4perl.appender.Screen            = Log::Log4perl::Appender::Screen
log4perl.appender.Screen.stderr     = 0
log4perl.appender.Screen.layout     = PatternLayout
log4perl.appender.Screen.layout.ConversionPattern = ${layout_pattern}
##log4perl.appender.Screen.Threshold = INFO
EOF

  return $LOG_CONF;
}

=back

=head2 Instance Methods

=over 2

=item ... 

=cut

=back

=cut


1;
__END__;


=head1 SEE ALSO



L<Log::Log4perl|Log::Log4perl>, 


=head1 AUTHOR / VERSION

  $Id$

=head1 COPYRIGHT AND LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut


