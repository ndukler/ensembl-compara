=head1 NAME

NestedSet - DESCRIPTION of Object

=head1 SYNOPSIS

=head1 DESCRIPTION

Abstract superclass to encapsulate the process of storing and manipulating a
nested-set representation tree.  Also implements a 'reference count' system 
based on the ObjectiveC retain/release design. 
Designed to be used as the Root class for all Compara 'proxy' classes 
(Member, GenomeDB, DnaFrag, NCBITaxon) to allow them to be made into sets and trees.

=head1 CONTACT

  Contact Jessica Severin on implemetation/design detail: jessica@ebi.ac.uk
  Contact Ewan Birney on EnsEMBL in general: birney@sanger.ac.uk

=head1 APPENDIX

The rest of the documentation details each of the object methods. Internal methods are usually preceded with a _

=cut

package Bio::EnsEMBL::Compara::NestedSet;

use strict;
use Bio::EnsEMBL::Utils::Exception;
use Bio::EnsEMBL::Utils::Argument;
use Data::UUID;

#################################################
# Factory methods
#################################################

sub new {
  my ($class, @args) = @_;
  my $self = {};

  bless $self,$class;
  $self->init;
  #printf("%s   CREATE refcount:%d\n", $self->node_id, $self->refcount);
  
  return $self;
}

sub init {
  my $self = shift;

  #internal variables minimal allocation
 # $self->{'_children_id_hash'} = {};
  $self->{'_node_id'} = undef;
  $self->{'_adaptor'} = undef;
  $self->{'_refcount'} = 0;

  return $self;
}

sub dealloc {
  my $self = shift;

  $self->release_children;
  #printf("DEALLOC refcount:%d ", $self->refcount); $self->print_node;
}

sub DESTROY {
  my $self = shift;
  if(defined($self->{'_refcount'}) and $self->{'_refcount'}>0) {
    printf("WARNING DESTROY refcount:%d  (%d)%s %s\n", $self->refcount, $self->node_id, $self->name, $self);
  }    
  $self->SUPER::DESTROY if $self->can("SUPER::DESTROY");
}


#######################################
# reference counting system
# DO NOT OVERRIDE
#######################################

sub retain {
  my $self = shift;
  $self->{'_refcount'}=0 unless(defined($self->{'_refcount'}));
  $self->{'_refcount'}++;
  #printf("RETAIN  refcount:%d ", $self->refcount); $self->print_node;
  return $self;
}

sub release {
  my $self = shift;
  throw("calling release on object which hasn't been retained") 
    unless(defined($self->{'_refcount'}));
  $self->{'_refcount'}--;
  #printf("RELEASE refcount:%d ", $self->refcount); $self->print_node;
  return $self if($self->refcount > 0);
  $self->dealloc;
  return undef;
}

sub refcount {
  my $self = shift;
  return $self->{'_refcount'};
}

#################################################
#
# get/set variable methods
#
#################################################

=head2 node_id

  Arg [1]    : (opt.) integer node_id
  Example    : my $nsetID = $object->node_id();
  Example    : $object->node_id(12);
  Description: Getter/Setter for the node_id of this object in the database
  Returntype : integer node_id
  Exceptions : none
  Caller     : general

=cut

sub node_id {
  my $self = shift;
  $self->{'_node_id'} = shift if(@_);
  unless(defined($self->{'_node_id'})) {
    $self->{'_node_id'} = Data::UUID->new->create_str();
  }
  return $self->{'_node_id'};
}


=head2 adaptor

  Arg [1]    : (opt.) Bio::EnsEMBL::Compara::DBSQL::MethodLinkSpeciesSetAdaptor
  Example    : my $object_adaptor = $object->adaptor();
  Example    : $object->adaptor($object_adaptor);
  Description: Getter/Setter for the adaptor this object uses for database
               interaction.
  Returntype : subclass of Bio::EnsEMBL::Compara::DBSQL::NestedSetAdaptor
  Exceptions : none
  Caller     : general

=cut

sub adaptor {
  my $self = shift;
  $self->{'_adaptor'} = shift if(@_);
  return $self->{'_adaptor'};
}


sub store {
  my $self = shift;
  throw("adaptor must be defined") unless($self->adaptor);
  $self->adaptor->store($self);
}



#######################################
# Set manipulation methods
#######################################

=head2 add_child

  Overview   : attaches child nestedset node to this nested set
  Arg [1]    : Bio::EnsEMBL::Compara::NestedSet $child
  Example    : $self->add_child($child);
  Returntype : undef
  Exceptions : if child is undef or not a NestedSet subclass
  Caller     : general

=cut

sub add_child {
  my ($self, $child) = @_;

  throw("child not defined") 
     unless(defined($child));
  throw("arg must be a [Bio::EnsEMBL::Compara::NestedSet] not a [$child]")
     unless($child->isa('Bio::EnsEMBL::Compara::NestedSet'));
  
  #print("add_child\n");  $self->print_node; $child->print_node;
  
  return undef if($self->{'_children_id_hash'}->{$child->node_id});

  #object linkage
  $child->retain->disavow_parent;
  $child->_set_parent($self);

  $self->{'_children_id_hash'} = {} unless($self->{'_children_id_hash'});
  $self->{'_children_id_hash'}->{$child->node_id} = $child;
  return undef;
}


sub store_child {
  my ($self, $child) = @_;

  throw("child not defined") 
     unless(defined($child));
  throw("arg must be a [Bio::EnsEMBL::Compara::NestedSet] not a [$child]")
     unless($child->isa('Bio::EnsEMBL::Compara::NestedSet'));
  throw("adaptor must be defined") unless($self->adaptor);

  $child->_set_parent($self);
  $self->adaptor->store($child);
}

=head2 remove_child

  Overview   : unlink and release child from self if its mine
               might cause child to delete if refcount reaches Zero.
  Arg [1]    : $child Bio::EnsEMBL::Compara::NestedSet instance
  Example    : $self->remove_child($child);
  Returntype : undef
  Caller     : general

=cut

sub remove_child {
  my ($self, $child) = @_;

  throw("child not defined") unless(defined($child));
  throw("arg must be a [Bio::EnsEMBL::Compara::NestedSet] not a [$child]")
     unless($child->isa('Bio::EnsEMBL::Compara::NestedSet'));
  throw("not my child")
    unless($self->{'_children_id_hash'} and 
           $self->{'_children_id_hash'}->{$child->node_id});
  
  delete $self->{'_children_id_hash'}->{$child->node_id};
  $child->_set_parent(undef);
  $child->release;
  return undef;
}


=head2 disavow_parent

  Overview   : unlink and release self from its parent
               might cause self to delete if refcount reaches Zero.
  Example    : $self->disavow_parent
  Returntype : undef
  Caller     : general

=cut

sub disavow_parent {
  my $self = shift;

  my $parent = $self->{'_parent_node'}; #use variable to bypass parent autoload
  $self->_set_parent(undef);
  if($parent) {
    $parent->remove_child($self);
    #print("DISAVOW parent : "); $parent->print_node;
    #print("        child  : "); $self->print_node;
  }
  return undef;
}


=head2 release_children

  Overview   : release all children and clear arrays and hashes
               will cause potential deletion of children if refcount reaches Zero.
  Example    : $self->release_children
  Returntype : $self
  Exceptions : none
  Caller     : general

=cut

sub release_children {
  my $self = shift;
  
  return $self unless($self->{'_children_id_hash'});

  my @kids = values(%{$self->{'_children_id_hash'}});
  foreach my $child (@kids) {
    #printf("  parent %d releasing child %d\n", $self->node_id, $child->node_id);
    if($child) {
      $child->release_children;
      $child->release;
    }
  }
  $self->{'_children_id_hash'} = undef;
  return $self;
}


=head2 parent

  Overview   : returns the parent NestedSet object for this node
  Example    : my $my_parent = $object->parent();
  Returntype : undef or Bio::EnsEMBL::Compara::NestedSet
  Exceptions : none
  Caller     : general

=cut

sub parent {
  my $self = shift;
  return $self->{'_parent_node'} if(defined($self->{'_parent_node'}));
  if($self->adaptor and $self->_parent_id) {
    my $parent = $self->adaptor->fetch_parent_for_node($self);
    #print("fetched parent : "); $parent->print_node;
    $parent->add_child($self);
  }
  return $self->{'_parent_node'};
}


sub has_parent {
  my $self = shift;
  return 1 if($self->{'_parent_node'} or $self->{'_parent_id'});
  return 0;
}


=head2 root

  Overview   : returns the root NestedSet object for this node
               returns $self if node has no parent (this is the root)
  Example    : my $root = $object->root();
  Returntype : undef or Bio::EnsEMBL::Compara::NestedSet
  Exceptions : none
  Caller     : general

=cut

sub root {
  my $self = shift;

  return $self unless(defined($self->parent));
  return $self->parent->root;
}

sub subroot {
  my $self = shift;

  return undef unless($self->parent);
  return $self unless(defined($self->parent->parent));
  return $self->parent->subroot;
}


=head2 children

  Overview   : returns a list of NestedSet nodes directly under this parent node
  Example    : my @children = @{$object->children()};
  Returntype : array reference of Bio::EnsEMBL::Compara::NestedSet objects (could be empty)
  Exceptions : none
  Caller     : general

=cut

sub children {
  my $self = shift;

  $self->load_children_if_needed;
  return [] unless($self->{'_children_id_hash'});
  my @kids = values(%{$self->{'_children_id_hash'}});
  return \@kids;
}


sub get_child_count {
  my $self = shift;
  return scalar(@{$self->children});
}

sub load_children_if_needed {
  my $self = shift;

  if($self->adaptor and !defined($self->{'_children_id_hash'})) {
    #define _children_id_hash thereby signally that I've tried to load my children
    $self->{'_children_id_hash'} = {}; 
    #print("fetch_all_children_for_node : "); $self->print_node;
    $self->adaptor->fetch_all_children_for_node($self);
  }
  return $self;
}


=head2 distance_to_parent

  Arg [1]    : (opt.) <int or double> distance
  Example    : my $dist = $object->distance_to_parent();
  Example    : $object->distance_to_parent(1.618);
  Description: Getter/Setter for the distance between this child and its parent
  Returntype : integer node_id
  Exceptions : none
  Caller     : general

=cut

sub distance_to_parent {
  my $self = shift;
  $self->{'_distance_to_parent'} = shift if(@_);
  $self->{'_distance_to_parent'} = 0.0 unless(defined($self->{'_distance_to_parent'}));
  return $self->{'_distance_to_parent'};
}

sub distance_to_root {
  my $self = shift;
  my $dist = $self->distance_to_parent;
  $dist += $self->parent->distance_to_root if($self->parent);
  return $dist;
}

sub left_index {
  my $self = shift;
  $self->{'_left_index'} = shift if(@_);
  $self->{'_left_index'} = 0 unless(defined($self->{'_left_index'}));
  return $self->{'_left_index'};
}

sub right_index {
  my $self = shift;
  $self->{'_right_index'} = shift if(@_);
  $self->{'_right_index'} = 0 unless(defined($self->{'_right_index'}));
  return $self->{'_right_index'};
}


sub print_tree {
  my $self  = shift;
  my $indent = shift;
  my $lastone = shift;

  $indent = '' unless(defined($indent));

  $self->print_node($indent);

  if($lastone) {
    chop($indent);
    $indent .= " ";
  }
  for(my $i=0; $i<$self->distance_to_parent()*30; $i++) { $indent .= ' '; }
  $indent .= "   |";


  my $children = $self->children;
  my $count=0;
  $lastone = 0;
  foreach my $child_node (@$children) {  
    $count++;
    $lastone = 1 if($count == scalar(@$children));
    $child_node->print_tree($indent,$lastone);
  }
}


sub print_node {
  my $self  = shift;
  my $indent = shift;

  $indent = '' unless(defined($indent));
  print($indent);
  #if($self->parent) {
  #  for(my $i=0; $i<$self->parent->distance_to_root()*30; $i++) { print(' '); }
  #}
  for(my $i=0; $i<$self->distance_to_parent()*30; $i++) { print('-'); }
  printf("(%s)", $self->node_id);
  printf("NS:%s\n", $self->name);
}


##################################
#
# Set theory methods
#
##################################

sub equals {
  my $self = shift;
  my $other = shift;
  throw("arg must be a [Bio::EnsEMBL::Compara::NestedSet] not a [$other]")
        unless($other->isa('Bio::EnsEMBL::Compara::NestedSet'));
  return 1 if($self->node_id eq $other->node_id);
  return 0;
}

sub has_child {
  my $self = shift;
  my $child = shift;
  throw("arg must be a [Bio::EnsEMBL::Compara::NestedSet] not a [$child]")
        unless($child->isa('Bio::EnsEMBL::Compara::NestedSet'));
  return 1 if($child->parent = $self);
  return 0;
}

sub has_child_with_node_id {
  my $self = shift;
  my $node_id = shift;
  $self->load_children_if_needed;
  return undef unless($self->{'_children_id_hash'});
  return $self->{'_children_id_hash'}->{$node_id};
}

sub is_member_of {
  my $A = shift;
  my $B = shift;
  return 1 if($B->has_child($A));
  return 0; 
}

sub is_not_member_of {
  my $A = shift;
  my $B = shift;
  return 0 if($B->has_child($A));
  return 1; 
}

sub is_subset_of {
  my $A = shift;
  my $B = shift;
  return 1; 
}

sub is_leaf {
  my $self = shift;
  return 1 unless($self->get_child_count);
  return 0;
}

sub merge_children {
  my $self = shift;
  my $nset = shift;
  throw("arg must be a [Bio::EnsEMBL::Compara::NestedSet] not a [$nset]")
        unless($nset->isa('Bio::EnsEMBL::Compara::NestedSet'));
  foreach my $child_node (@{$nset->children}) {
    $self->add_child($child_node);
  }
  return $self;
}

sub merge_node_via_shared_ancestor {
  my $self = shift;
  my $node = shift;

  my $node_dup = $self->find_node_by_node_id($node->node_id);
  if($node_dup) {
    warn("trying to merge in a node with already exists\n");
    return $node_dup;
  }
  return undef unless($node->parent);
  
  my $ancestor = $self->find_node_by_node_id($node->parent->node_id);
  if($ancestor) {
    $ancestor->add_child($node);
    print("common ancestor at : "); $ancestor->print_node;
    return $ancestor;
  }
  return $self->merge_node_via_shared_ancestor($node->parent);
}

##################################
#
# nested_set manipulations
#
##################################

sub flatten_tree {
  my $self = shift;
  
  my $leaves = $self->get_all_leaves;
  foreach my $leaf (@{$leaves}) { $leaf->retain->disavow_parent; }

  $self->release_children;
  foreach my $leaf (@{$leaves}) { $self->add_child($leaf); $leaf->release; }
  
  return $self;
}

##################################
#
# search methods
#
##################################

sub find_node_by_name {
  my $self = shift;
  my $name = shift;
  
  return $self if($name eq $self->name);
  
  my $children = $self->children;
  foreach my $child_node (@$children) {
    my $found = $child_node->find_node_by_name($name);
    return $found if(defined($found));
  }
  
  return undef;
}

sub find_node_by_node_id {
  my $self = shift;
  my $node_id = shift;
  
  return $self if($node_id eq $self->node_id);
  
  my $children = $self->children;
  foreach my $child_node (@$children) {
    my $found = $child_node->find_node_by_node_id($node_id);
    return $found if(defined($found));
  }
  
  return undef;
}


=head2 get_all_leaves

 Title   : get_all_leaves
 Usage   : my @leaves = @{$tree->get_all_leaves};
 Function: searching from the given starting node, searches and creates list
           of all leaves in this subtree and returns by reference
 Example :
 Returns : reference to list of NestedSet objects (all leaves)
 Args    : none

=cut

sub get_all_leaves {
  my $self = shift;
  
  my $leaves = {};
  $self->_recursive_get_all_leaves($leaves);
  my @leaf_list = values(%{$leaves});
  return \@leaf_list;
}

sub _recursive_get_all_leaves {
  my $self = shift;
  my $leaves = shift;
    
  $leaves->{$self->node_id} = $self if($self->is_leaf);

  foreach my $child (@{$self->children}) {
    $child->_recursive_get_all_leaves($leaves);
  }
  return undef;
}


=head2 max_depth

 Title   : max_depth
 Args    : none
 Usage   : $tree_node->max_depth;
 Function: searching from the given starting node, calculates the maximum depth to a leaf
 Returns : int

=cut

sub max_depth {
  my $self = shift;

  my $max_depth = 0;
  
  foreach my $child (@{$self->children}) {
    my $depth = $child->max_depth;
    $max_depth=$depth if($depth>$max_depth);
  }
  return $max_depth;  
}


##################################
#
# developer/adaptor API methods
#
##################################

sub name {
  my $self = shift;
  $self->{'_name'} = shift if(@_);
  $self->{'_name'} = '' unless(defined($self->{'_name'}));
  return $self->{'_name'};
}


# used for building tree from a DB fetch, want to restrict users to create trees
# by only -add_child method
sub _set_parent {
  my ($self, $parent) = @_;
  $self->{'_parent_id'} = 0;
  $self->{'_parent_node'} = $parent;
  $self->{'_parent_id'} = $parent->node_id if($parent);
  return $self;
}


# used for building tree from a DB fetch until all the objects are in memory
sub _parent_id {
  my $self = shift;
  $self->{'_parent_id'} = shift if(@_);
  return $self->{'_parent_id'};
}

# used for building tree from a DB fetch until all the objects are in memory
sub _root_id {
  my $self = shift;
  $self->{'_root_id'} = shift if(@_);
  return $self->{'_root_id'};
}


1;

