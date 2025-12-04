#!/usr/bin/perl

# ------------------------------------------------------------------------------
use strict;
use warnings;

# ------------------------------------------------------------------------------
my ( $INLINE_DIR, $SELF_NAME, $PID_FILE, $ICON_PATH );

# ------------------------------------------------------------------------------
BEGIN {
    use English qw/-no_match_vars/;
    use File::Basename;
    use File::Path          qw/make_path/;
    use File::Util::Tempdir qw/get_user_tempdir/;
    $SELF_NAME  = basename($PROGRAM_NAME);
    $PID_FILE   = sprintf '%s/%s.pid', get_user_tempdir(), $SELF_NAME;
    $ICON_PATH  = dirname($PROGRAM_NAME) . '/i';
    $INLINE_DIR = sprintf '%s/%s.inline', get_user_tempdir(), $SELF_NAME;
    make_path($INLINE_DIR);
}

# ------------------------------------------------------------------------------
use Const::Fast;
use Daemon::Daemonize qw/check_pidfile delete_pidfile write_pidfile/;
use Getopt::Long;
use Gtk3 qw/-init/;
use Inline ( Config => directory => $INLINE_DIR, );
use Inline (
    C    => 'DATA',
    libs => '-lX11',
);
use Sys::SigAction qw/set_sig_handler/;
use Try::Catch;
use X11::IdleTime;

# ------------------------------------------------------------------------------
const my $SEC_IN_MIN => 60;
const my @TERMSIG    => qw/INT TERM QUIT PIPE ABRT BUS FPE ILL SEGV SYS STOP TRAP/;
our $VERSION = '1.01';

# ------------------------------------------------------------------------------
check_pidfile($PID_FILE) and _error('Already loaded');
try {
    write_pidfile($PID_FILE);
}
catch {
    _error($_);
};

my %opt = ( i => 'kb', );
GetOptions(
    'i=s' => \$opt{i},
    't=i' => \$opt{t},
    'l'   => \$opt{l},
) or _help();
if ( $opt{t} ) {
    $opt{t} > 0 or _help();
}
_load_icons();

# ------------------------------------------------------------------------------
my ( $locked, $ICON_ON, $ICON_OFF ) = (0);
my $trayicon = Gtk3::StatusIcon->new;
$trayicon->set_tooltip_text("Left click: switch locking\nRight click: unlock and exit");
$trayicon->set_from_pixbuf($ICON_ON);
$opt{l} and _lock();
set_sig_handler $_,     \&_term for @TERMSIG;
set_sig_handler 'USR1', \&_lock;
set_sig_handler 'USR2', \&_unlock;
set_sig_handler 'HUP',  \&_switch;
$trayicon->signal_connect(
    'button_press_event' => sub {
        my ( undef, $event ) = @_;
        if ( $event->button == 3 ) {
            Gtk3->main_quit;
        }
        elsif ( $event->button == 1 ) {
            _switch();
        }
        return 1;
    }
);
if ( $opt{t} ) {
    $opt{t} *= $SEC_IN_MIN;
    set_sig_handler 'ALRM', \&_alarm;
    alarm $SEC_IN_MIN - 1;
}

Gtk3->main;
_term();

# ------------------------------------------------------------------------------
sub _term
{
    _unlock();
    delete_pidfile($PID_FILE);
    return exit 0;
}

# ------------------------------------------------------------------------------
sub _alarm
{
    if ( !$locked ) {
        my $idle = GetIdleTime();
        $idle >= $opt{t} and _lock();
    }
    return alarm $SEC_IN_MIN;
}

# ------------------------------------------------------------------------------
sub _lock
{
    if ( !$locked ) {
        if ( !xkb_lock() ) {
            $trayicon->set_from_pixbuf($ICON_OFF);
            $locked = 1;
        }
    }
    return $locked;
}

# ------------------------------------------------------------------------------
sub _unlock
{
    if ($locked) {
        if ( !xkb_unlock() ) {
            $trayicon->set_from_pixbuf($ICON_ON);
            $locked = 0;
        }
    }
    return $locked;
}

# ------------------------------------------------------------------------------
sub _switch
{
    return $locked ? _unlock() : _lock();
}

# ------------------------------------------------------------------------------
sub _help
{
    return _error(
        sprintf
            "Usage: %s options:\n  -t=MINUTES (timeout)\n  -l (lock after start)\n  -i=PREFIX (icons: i/lock/PREFIX.png, i/unlock/PREFIX.png)",
        $SELF_NAME
    );
}

# ------------------------------------------------------------------------------
sub _error
{
    my ($msg) = @_;

    my $dialog = Gtk3::Dialog->new( sprintf( '%s v %s', $SELF_NAME, $VERSION ),
        undef, 'destroy-with-parent', 'gtk-ok' => 'none' );
    my $label = Gtk3::Label->new("\n$msg\n");
    $dialog->get_content_area()->add($label);
    $dialog->signal_connect( response => sub { Gtk3->main_quit } );
    $dialog->show_all;
    Gtk3->main;
    exit 1;
}

# ------------------------------------------------------------------------------
sub _load_icons
{
    my $file_on  = sprintf '%s/unlock/%s.png', $ICON_PATH, $opt{i};
    my $file_off = sprintf '%s/lock/%s.png',   $ICON_PATH, $opt{i};
    try {
        $ICON_ON = Gtk3::Gdk::Pixbuf->new_from_file($file_on);
    }
    catch {
        _error( sprintf "Error loading ON icon '%s'\n%s", $file_on, $_ );
    };
    try {
        $ICON_OFF = Gtk3::Gdk::Pixbuf->new_from_file($file_off);
    }
    catch {
        _error( sprintf "Error loading OFF icon '%s'\n%s", $file_off, $_ );
    };
    return;
}

# ------------------------------------------------------------------------------
__END__
__C__

/* -------------------------------------------------------------------------- */
#include <X11/Xlib.h>

/* -------------------------------------------------------------------------- */
Display * display = NULL;
Window window = 0;

/* -------------------------------------------------------------------------- */
void xkb_unlock() 
{
    if( window && display ) { 
        XDestroyWindow( display, window );
    }    
    window = 0;
    if( display ) {
        XCloseDisplay( display );
        display = NULL;
    }
}

/* -------------------------------------------------------------------------- */
const char * xkb_lock() 
{
    if ( !display ) display = XOpenDisplay(0);
    if ( !display ) return "can not open display";
 
    XSetWindowAttributes attrib = { 0 };
    attrib.override_redirect = True;
    window = XCreateWindow( display, 
                            DefaultRootWindow(display),
                            0, 0, 
                            1, 1, 
                            0, 
                            CopyFromParent, 
                            InputOnly, 
                            CopyFromParent,
                            CWOverrideRedirect, 
                            &attrib );
                        
    XSelectInput( display, window, KeyPressMask|KeyReleaseMask );
    XMapWindow( display, window );
    
    if ( XGrabKeyboard( display, 
                        window, False, GrabModeAsync, 
                        GrabModeAsync, CurrentTime ) != GrabSuccess ) {
        xkb_unlock();
        return "can not grab keyboard";
    }
    return NULL;
}

/* -------------------------------------------------------------------------- */
