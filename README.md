# Git::PurePerl

This is a Perl 6 port of Perl 5's Git::PurePerl. It is a very young experiment,
runs extremely slowly at this time, and also will not work with any but the
most bleeding-edge Rakudos (after Mar 23 2015), due to a required bugfix to
pack(). Its first goals are basic cloning and checkouts to ease Panda's
portability woes.

In spite of the name, both this module and its P5 progenitor rely on a zlib DLL
or .so being available. Luckily, Perl 6's Compress::Zlib downloads a DLL for
Windows when one is not found at install time, and any non-Win system which
runs Rakudo probably already has zlib available, so this module should be as
portable as expected.

In its current state, it can be used to download a packfile over the git
protocol, like so:

Git::PurePerl.new(:directory\<target-dir>).clone: 'git://url.to/repo.git';

When cloning, the packfiles are downloaded and indexes are built for them. This
is very slow and takes a long time even for small repos so don't worry if there
is no output for a long time.

A few files other than packfiles are generated in a new .git directory if one
does not already exist, but it is not complete e.g. .git/config doesn't exist.

The clone is always initialized to the 'master' branch but no actual checkout
is performed yet, so there will be no project files in the directory unless
something like git reset --hard is used manually.
