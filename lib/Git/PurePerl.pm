class Git::PurePerl;
use Git::PurePerl::Protocol;
use Git::PurePerl::Pack::WithoutIndex;

has IO::Path $.directory;
has IO::Path $.gitdir = self.directory.child: '.git';

submethod BUILD (:$directory is copy, :$gitdir is copy, |args) {
    $directory .= IO unless $directory ~~ IO::Path;
    $!directory = $directory;
    if defined $gitdir {
        $gitdir .= IO unless $gitdir ~~ IO::Path;
        $!gitdir = $gitdir;
    }
}

#`[[[
has $.loose is rw =
    Git::PurePerl::Loose.new: directory => $.gitdir.child: 'objects';

has @.packs is rw =
    $.gitdir.child('objects').child('pack').dir(test => /\.pack$/).map: {
        Git::PurePerl::Pack::WithIndex.new: :filename($_)
    };

has $.description = $.gitdir.child('description').slurp.chomp;

has $.config = Git::PurePerl::Config.new;
]]]

#`[[[
sub _ref_names_recursive {
    my ( $dir, $base, $names ) = @_;

    foreach my $file ( $dir->children ) {
        if ( -d $file ) {
            my $reldir  = $file->relative($dir);
            my $subbase = $base . $reldir . "/";
            _ref_names_recursive( $file, $subbase, $names );
        } else {
            push @$names, $base . $file->basename;
        }
    }
}

sub ref_names {
    my $self = shift;
    my @names;
    foreach my $type (qw(heads remotes tags)) {
        my $dir = dir( $self->gitdir, 'refs', $type );
        next unless -d $dir;
        my $base = "refs/$type/";
        _ref_names_recursive( $dir, $base, \@names );
    }
    my $packed_refs = file( $self->gitdir, 'packed-refs' );
    if ( -f $packed_refs ) {
        foreach my $line ( $packed_refs->slurp( chomp => 1 ) ) {
            next if $line =~ /^#/;
            next if $line =~ /^\^/;
            my ( $sha1, my $name ) = split ' ', $line;
            push @names, $name;
        }
    }
    return @names;
}

sub refs_sha1 {
    my $self = shift;
    return map { $self->ref_sha1($_) } $self->ref_names;
}

sub refs {
    my $self = shift;
    return map { $self->ref($_) } $self->ref_names;
}

sub ref_sha1 {
    my ( $self, $wantref ) = @_;
    my $dir = dir( $self->gitdir, 'refs' );
    return unless -d $dir;

    if ($wantref eq "HEAD") {
        my $file = file($self->gitdir, 'HEAD');
        my $sha1 = file($file)->slurp
            || confess("Error reading $file: $!");
        chomp $sha1;
        return _ensure_sha1_is_sha1( $self, $sha1 );
    }

    foreach my $file ( File::Find::Rule->new->file->in($dir) ) {
        my $ref = 'refs/' . file($file)->relative($dir)->as_foreign('Unix');
        if ( $ref eq $wantref ) {
            my $sha1 = file($file)->slurp
                || confess("Error reading $file: $!");
            chomp $sha1;
            return _ensure_sha1_is_sha1( $self, $sha1 );
        }
    }

    my $packed_refs = file( $self->gitdir, 'packed-refs' );
    if ( -f $packed_refs ) {
        my $last_name;
        my $last_sha1;
        foreach my $line ( $packed_refs->slurp( chomp => 1 ) ) {
            next if $line =~ /^#/;
            my ( $sha1, my $name ) = split ' ', $line;
            $sha1 =~ s/^\^//;
            $name ||= $last_name;

            return _ensure_sha1_is_sha1( $self, $last_sha1 ) if $last_name and $last_name eq $wantref and $name ne $wantref;

            $last_name = $name;
            $last_sha1 = $sha1;
        }
        return _ensure_sha1_is_sha1( $self, $last_sha1 ) if $last_name eq $wantref;
    }
    return undef;
}

sub _ensure_sha1_is_sha1 {
    my ( $self, $sha1 ) = @_;
    return $self->ref_sha1($1) if $sha1 =~ /^ref: (.*)/;
    return $sha1;
}

sub ref {
    my ( $self, $wantref ) = @_;
    return $self->get_object( $self->ref_sha1($wantref) );
}

sub master_sha1 {
    my $self = shift;
    return $self->ref_sha1('refs/heads/master');
}

sub master {
    my $self = shift;
    return $self->ref('refs/heads/master');
}

sub head_sha1 {
    my $self = shift;
    return $self->ref_sha1('HEAD');
}

sub head {
    my $self = shift;
    return $self->ref('HEAD');
}

sub get_object {
    my ( $self, $sha1 ) = @_;
    return unless $sha1;
    return $self->get_object_packed($sha1) || $self->get_object_loose($sha1);
}

sub get_objects {
    my ( $self, @sha1s ) = @_;
    return map { $self->get_object($_) } @sha1s;
}

sub get_object_packed {
    my ( $self, $sha1 ) = @_;

    foreach my $pack ( $self->packs ) {
        my ( $kind, $size, $content ) = $pack->get_object($sha1);
        if ( defined($kind) && defined($size) && defined($content) ) {
            return $self->create_object( $sha1, $kind, $size, $content );
        }
    }
}

sub get_object_loose {
    my ( $self, $sha1 ) = @_;

    my ( $kind, $size, $content ) = $self->loose->get_object($sha1);
    if ( defined($kind) && defined($size) && defined($content) ) {
        return $self->create_object( $sha1, $kind, $size, $content );
    }
}

sub create_object {
    my ( $self, $sha1, $kind, $size, $content ) = @_;
    if ( $kind eq 'commit' ) {
        return Git::PurePerl::Object::Commit->new(
            sha1    => $sha1,
            kind    => $kind,
            size    => $size,
            content => $content,
            git     => $self,
        );
    } elsif ( $kind eq 'tree' ) {
        return Git::PurePerl::Object::Tree->new(
            sha1    => $sha1,
            kind    => $kind,
            size    => $size,
            content => $content,
            git     => $self,
        );
    } elsif ( $kind eq 'blob' ) {
        return Git::PurePerl::Object::Blob->new(
            sha1    => $sha1,
            kind    => $kind,
            size    => $size,
            content => $content,
            git     => $self,
        );
    } elsif ( $kind eq 'tag' ) {
        return Git::PurePerl::Object::Tag->new(
            sha1    => $sha1,
            kind    => $kind,
            size    => $size,
            content => $content,
            git     => $self,
        );
    } else {
        confess "unknown kind $kind: $content";
    }
}

sub all_sha1s {
    my $self = shift;
    my $dir = dir( $self->gitdir, 'objects' );

    my @streams;
    push @streams, $self->loose->all_sha1s;

    foreach my $pack ( $self->packs ) {
        push @streams, $pack->all_sha1s;
    }

    return Data::Stream::Bulk::Cat->new( streams => \@streams );
}

sub all_objects {
    my $self   = shift;
    my $stream = $self->all_sha1s;
    return Data::Stream::Bulk::Filter->new(
        filter => sub { return [ $self->get_objects(@$_) ] },
        stream => $stream,
    );
}

sub put_object {
    my ( $self, $object, $ref ) = @_;
    $self->loose->put_object($object);

    if ( $object->kind eq 'commit' ) {
        $ref = 'master' unless $ref;
        $self->update_ref( $ref, $object->sha1 );
    }
}
]]]

method update_ref ($refname, $sha1) {
    my $ref = $.gitdir.child('refs').child('heads').child($refname);
    $ref.parent.mkdir;
    $ref.spurt: $sha1;

    # FIXME is this always what we want?
    $.gitdir.child('HEAD').spurt: "ref: refs/heads/$refname";
}

#`[[[
sub init {
    my ( $class, %arguments ) = @_;

    my $directory = $arguments{directory};
    my $git_dir;

    unless ( defined $directory ) {
        $git_dir = $arguments{gitdir}
            || confess
            "init() needs either a 'directory' or a 'gitdir' argument";
    } else {
        if ( not defined $arguments{gitdir} ) {
            $git_dir = $arguments{gitdir} = dir( $directory, '.git' );
        }
        dir($directory)->mkpath;
    }

    dir($git_dir)->mkpath;
    dir( $git_dir, 'refs',    'tags' )->mkpath;
    dir( $git_dir, 'objects', 'info' )->mkpath;
    dir( $git_dir, 'objects', 'pack' )->mkpath;
    dir( $git_dir, 'branches' )->mkpath;
    dir( $git_dir, 'hooks' )->mkpath;

    my $bare = defined($directory) ? 'false' : 'true';
    $class->_add_file(
        file( $git_dir, 'config' ),
        "[core]\n\trepositoryformatversion = 0\n\tfilemode = true\n\tbare = $bare\n\tlogallrefupdates = true\n"
    );
    $class->_add_file( file( $git_dir, 'description' ),
        "Unnamed repository; edit this file to name it for gitweb.\n" );
    $class->_add_file(
        file( $git_dir, 'hooks', 'applypatch-msg' ),
        "# add shell script and make executable to enable\n"
    );
    $class->_add_file( file( $git_dir, 'hooks', 'post-commit' ),
        "# add shell script and make executable to enable\n" );
    $class->_add_file(
        file( $git_dir, 'hooks', 'post-receive' ),
        "# add shell script and make executable to enable\n"
    );
    $class->_add_file( file( $git_dir, 'hooks', 'post-update' ),
        "# add shell script and make executable to enable\n" );
    $class->_add_file(
        file( $git_dir, 'hooks', 'pre-applypatch' ),
        "# add shell script and make executable to enable\n"
    );
    $class->_add_file( file( $git_dir, 'hooks', 'pre-commit' ),
        "# add shell script and make executable to enable\n" );
    $class->_add_file( file( $git_dir, 'hooks', 'pre-rebase' ),
        "# add shell script and make executable to enable\n" );
    $class->_add_file( file( $git_dir, 'hooks', 'update' ),
        "# add shell script and make executable to enable\n" );

    dir( $git_dir, 'info' )->mkpath;
    $class->_add_file( file( $git_dir, 'info', 'exclude' ),
        "# *.[oa]\n# *~\n" );

    return $class->new(%arguments);
}

sub checkout {
    my ( $self, $directory, $tree ) = @_;
    $directory ||= $self->directory;
    $tree ||= $self->master->tree;
    confess("Missing tree") unless $tree;
    foreach my $directory_entry ( $tree->directory_entries ) {
        my $filename = file( $directory, $directory_entry->filename );
        my $sha1     = $directory_entry->sha1;
        my $mode     = $directory_entry->mode;
        my $object   = $self->get_object($sha1);
        if ( $object->kind eq 'blob' ) {
            $self->_add_file( $filename, $object->content );
            chmod( oct( '0' . $mode ), $filename )
                || die "Error chmoding $filename to $mode: $!";
        } elsif ( $object->kind eq 'tree' ) {
            dir($filename)->mkpath;
            $self->checkout( $filename, $object );
        } else {
            die $object->kind;
        }
    }
}
]]]

method clone ($remote) {
    my $protocol = Git::PurePerl::Protocol.new: :$remote;

    my %sha1s = $protocol.connect;
    my $head  = %sha1s<HEAD>;
    my $data  = $protocol.fetch_pack: $head;

    my $filename = $.gitdir.child('objects').child('pack').child("pack-$head.pack");
    self._add_file: $filename, $data;

    my $pack = Git::PurePerl::Pack::WithoutIndex.new: :$filename;
    $pack.create_index();

    self.update_ref: 'master', $head;
}

method _add_file ($filename, Blob $contents) {
    $filename.parent.mkdir;
    $filename.spurt: $contents;
}

# vim: ft=perl6
