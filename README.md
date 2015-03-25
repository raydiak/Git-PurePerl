# Git::PurePerl

This is a Perl 6 port of Perl 5's Git::PurePerl. *It is not currently
functional.* Its first goals are basic cloning and checkouts to ease Panda's
portability woes.

In its current state, it can be used to download a packfile over the git
protocol, like so:

Git::PurePerl.new(:directory\<target-dir>).clone: 'git://url.to/repo.git';

When cloning, it will fail an attempt to build an index for the packfile. This
is where progress left off.
