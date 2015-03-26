class Git::PurePerl::Object;

my Str enum ObjectKind is export (:commit<commit>, :tree<tree>, :blob<blob>, :tag<tag>);

has ObjectKind $.kind = die 'kind is required';
has Int $.size = die 'size is required';
has Str $.content is rw = die 'content is required';
has Str $.sha1 = die 'sha1 is required';
has $.git = die 'git is required';

# vim: ft=perl6
