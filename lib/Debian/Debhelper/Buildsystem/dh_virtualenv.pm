package Debian::Debhelper::Buildsystem::dh_virtualenv;

use strict;
use base 'Debian::Debhelper::Buildsystem';
use Debian::Debhelper::Dh_Lib;
use File::Spec;
use Cwd;

sub DESCRIPTION {
    'Python Virtualenv';
}

sub DEFAULT_BUILD_DIRECTORY {
        my $this=shift;
        return $this->canonpath($this->get_sourcepath("build"));
}

sub check_auto_buildable {
        my $this=shift;
        return -e $this->get_sourcepath("setup.py") ? 1 : 0;
}

sub new {
    my $class = shift;
    my $this = $class->SUPER::new(@_);
    $this->prefer_out_of_source_building();
    return $this;
}

sub get_install_root {
    my $prefix = "/usr/share/python";
    if (defined $ENV{DH_VIRTUALENV_INSTALL_ROOT}) {
        $prefix = $ENV{DH_VIRTUALENV_INSTALL_ROOT};
    }
    return $prefix;
}

sub get_venv_builddir {
    my $this = shift;
    my $builddir = $this->get_builddir();
    my $sourcepackage = $this->sourcepackage();
    my $prefix = $this->get_install_root();
    return "$builddir$prefix/$sourcepackage";
}

sub get_exec {
    my $this = shift;
    my $executable = shift;
    my $builddir = $this->get_venv_builddir();
    return Cwd::abs_path("$builddir/bin/$executable");
}

sub get_python {
    my $this = shift;
    return $this->get_exec("python");
}

sub get_pip {
    my $this = shift;
    return $this->get_exec("pip");
}

sub configure {
    my $this = shift;
    doit('mkdir', '-p', $this->get_venv_builddir());
}

sub build {
    my $this = shift;
    my $sourcedir = $this->get_sourcedir();
    my $builddir = $this->get_venv_builddir();
    my @params = ('--no-site-packages');
    my $reqfile = ('requirements.txt');
    my @pipargs = ();

    if (defined $ENV{DH_VIRTUALENV_ARGUMENTS}) {
        @params = split(' ', $ENV{DH_VIRTUALENV_ARGUMENTS});
    }

    if (defined $ENV{DH_REQUIREMENTS_FILE}) {
        $reqfile = $ENV{DH_REQUIREMENTS_FILE};
    }

    if (defined $ENV{DH_PIP_EXTRA_ARGS}) {
        @pipargs = split(' ', $ENV{DH_PIP_EXTRA_ARGS});
    }

    $this->doit_in_builddir(
        'virtualenv', @params, Cwd::abs_path($builddir));

    my $python = $this->get_python();
    my $pip = $this->get_pip();

    $this->doit_in_sourcedir(
        $python, $pip, 'install', '-r', $reqfile, @pipargs);

    $this->doit_in_sourcedir(
        $python, $pip, 'install', '.');

}

sub test {
    my $this = shift;
    my $python = $this->get_python();
    $this->doit_in_sourcedir(
        $python, 'setup.py', 'test');
}

sub install {
    my $this = shift;
    my $destdir = shift;
    my $pip = $this->get_pip();
    my $python = $this->get_python();
    my $sourcepackage = $this->sourcepackage();
    my $venv = $this->get_venv_builddir();
    my $prefix = $this->get_install_root();

    # Before we copy files, let's make the symlinks in the 'usr/local'
    # relative to the build path.
    my @files_in_local = <"$venv/local/*">;
    foreach (@files_in_local) {
        if ( -l $_ ) {
            my $target = readlink;
            my $relpath = File::Spec->abs2rel($target, "$venv/local");
            my $basename = Debian::Debhelper::Dh_Lib->basename($_);
            unlink;
            symlink($relpath, $_);
       }
    }

    $this->doit_in_builddir('mkdir', '-p', $destdir);
    $this->doit_in_builddir('cp', '-r', '-T', '.', $destdir);

    my $new_python = "$prefix/$sourcepackage/bin/python";

    # Fix shebangs so that we use the Python in the final location
    # instead of the Python in the build directory
    my @binaries = <"$destdir$prefix/$sourcepackage/bin/*">;
    {
        local $^I = q{};
        local @ARGV = grep { -T } @binaries;
        while ( <> ) {
            s|^#!.*bin/(env )?python|#!$new_python|;
            print;
        }
    }
}

sub clean {
    my $this = shift;
    $this->rmdir_builddir();
}

1
