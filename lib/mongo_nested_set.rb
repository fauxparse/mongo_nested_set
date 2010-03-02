module MongoNestedSet
  def self.included(base)
    base.extend(SingletonMethods)
  end
  
  module SingletonMethods
    def acts_as_nested_set(options = {})
      options = {
        :parent_column => 'parent_id',
        :left_column => 'lft',
        :right_column => 'rgt',
        :dependent => :delete_all, # or :destroy
      }.merge(options)
      
      if options[:scope].is_a?(Symbol) && options[:scope].to_s !~ /_id$/
        options[:scope] = "#{options[:scope]}_id".intern
      end

      write_inheritable_attribute :acts_as_nested_set_options, options
      class_inheritable_reader :acts_as_nested_set_options
      
      unless self.is_a?(ClassMethods)
        include Comparable
        include Columns
        include InstanceMethods
        extend Columns
        extend ClassMethods
        
        belongs_to :parent, :class_name => self.base_class.to_s,
          :foreign_key => parent_column_name
        many :children, :class_name => self.base_class.to_s,
          :foreign_key => parent_column_name, :order => quoted_left_column_name

        attr_accessor :skip_before_destroy
      
        key left_column_name.intern, Integer
        key right_column_name.intern, Integer
        key parent_column_name.intern, ObjectId
      
        # no bulk assignment
        # if accessible_attributes.blank?
        #   attr_protected  left_column_name.intern, right_column_name.intern 
        # end
                      
        before_create  :set_default_left_and_right
        before_save    :store_new_parent
        after_save     :move_to_new_parent
        before_destroy :destroy_descendants
                      
        # no assignment to structure fields
        # [left_column_name, right_column_name].each do |column|
        #   module_eval <<-"end_eval", __FILE__, __LINE__
        #     def #{column}=(x)
        #       raise "Unauthorized assignment to #{column}: it's an internal field handled by acts_as_nested_set code, use move_to_* methods instead."
        #     end
        #   end_eval
        # end
      
        # named_scope :roots, :conditions => {parent_column_name => nil}, :order => quoted_left_column_name
        # named_scope :leaves, :conditions => "#{quoted_right_column_name} - #{quoted_left_column_name} = 1", :order => quoted_left_column_name

        define_callbacks("before_move", "after_move")
      end
    end
  end
  
  module ClassMethods
    def base_class
      if superclass == Object
        self
      else
        super
      end
    end

    # Returns the first root
    def root
      first :parent_id => nil
    end

    def roots
      all :parent_id => nil, :order => "#{left_column_name} ASC"
    end
    
    def valid?
      left_and_rights_valid? && no_duplicates_for_columns? && all_roots_valid?
    end
    
    def left_and_rights_valid?
      all.detect { |node|
        node.send(left_column_name).nil? ||
        node.send(right_column_name).nil? ||
        node.send(left_column_name) >= node.send(right_column_name) ||
        !node.parent.nil? && (
          node.send(left_column_name) <= node.parent.send(left_column_name) ||
          node.send(right_column_name) >= node.parent.send(right_column_name)
        )
      }.nil?
    end
    
    def no_duplicates_for_columns?
      all.inject(true) { |memo, node|
        memo && [left_column_name, right_column_name].inject(true) { |v, column|
          v && count(node.scoped(column.to_sym => node.send(column))) == 1
        }
      }
    end
    
    # Wrapper for each_root_valid? that can deal with scope.
    def all_roots_valid?
      if acts_as_nested_set_options[:scope]
        roots.group_by{|record| scope_column_names.collect{|col| record.send(col.to_sym)}}.all? do |scope, grouped_roots|
          each_root_valid?(grouped_roots)
        end
      else
        each_root_valid?(roots)
      end
    end
    
    def each_root_valid?(roots_to_validate)
      left = right = 0
      roots_to_validate.all? do |root|
        returning(root.left > left && root.right > right) do
          left = root.left
          right = root.right
        end
      end
    end
            
    # Rebuilds the left & rights if unset or invalid.  Also very useful for converting from acts_as_tree.
    def rebuild!
      # Don't rebuild a valid tree.
      return true if valid?
      
      scope = lambda{ |node| {} }
      if acts_as_nested_set_options[:scope]
        scope = lambda { |node|
          scope_column_names.inject({}) { |hash, column_name|
            hash[column_name] = node.send(column_name.to_sym)
            hash
          }
        }
      end
      indices = {}
      
      set_left_and_rights = lambda do |node|
        # set left
        node.send(:"#{left_column_name}=", (indices[scope.call(node)] += 1))
        # find
        all(scope.call(node).merge(parent_column_name => node.id)).each { |n| set_left_and_rights.call(n) }
        # set right
        node.send(:"#{right_column_name}=", (indices[scope.call(node)] += 1))
        node.save!    
      end
                          
      # Find root node(s)
      root_nodes = all(parent_column_name => nil, :order => "#{left_column_name}, #{right_column_name}, id").each do |root_node|
        # setup index for this scope
        indices[scope.call(root_node)] ||= 0
        set_left_and_rights.call(root_node)
      end
    end

    # Iterates over tree elements and determines the current level in the tree.
    # Only accepts default ordering, odering by an other column than lft
    # does not work. This method is much more efficent than calling level
    # because it doesn't require any additional database queries.
    #
    # Example:
    #    Category.each_with_level(Category.root.self_and_descendants) do |o, level|
    #
    def each_with_level(objects)
      path = [nil]
      objects.sort_by(&left_column_name.to_sym).each do |o|
        if o._parent_id != path.last
          # we are on a new level, did we decent or ascent?
          if path.include?(o._parent_id)
            # remove wrong wrong tailing paths elements
            path.pop while path.last != o._parent_id
          else
            path << o._parent_id
          end
        end
        yield(o, path.length - 1)
      end
    end
  end

  # Mixed into both classes and instances to provide easy access to the column names
  module Columns
    def left_column_name
      acts_as_nested_set_options[:left_column]
    end
    
    def right_column_name
      acts_as_nested_set_options[:right_column]
    end
    
    def parent_column_name
      acts_as_nested_set_options[:parent_column]
    end
    
    def scope_column_names
      Array(acts_as_nested_set_options[:scope])
    end
    
    def quoted_left_column_name
      left_column_name
    end
    
    def quoted_right_column_name
      right_column_name
    end
    
    def quoted_parent_column_name
      parent_column_name
    end
    
    def quoted_scope_column_names
      scope_column_names
    end
  end

  module InstanceMethods
    def base_class
      self.class.base_class
    end
    
    # Value of the parent column
    def _parent_id
      send parent_column_name
    end
    
    # Value of the left column
    def left
      send left_column_name
    end
    
    # Value of the right column
    def right
      send right_column_name
    end

    # Returns true if this is a root node.
    def root?
      _parent_id.nil?
    end
    
    def leaf?
      !new? && right - left == 1
    end

    # Returns true is this is a child node
    def child?
      !_parent_id.nil?
    end

    # order by left column
    def <=>(x)
      left <=> x.left
    end
    
    # Redefine to act like active record
    def ==(comparison_object)
      comparison_object.equal?(self) ||
        (comparison_object.instance_of?(self.class) &&
          comparison_object.id == id &&
          !comparison_object.new?)
    end
    
    def scope_hash
      Hash[*Array(acts_as_nested_set_options[:scope]).collect { |s| [s, send(s)] }.flatten].merge(:order => "lft ASC")
    end
    
    def scoped(conditions = {})
      conditions.reverse_merge(scope_hash)
    end

    # Returns root
    def root
      base_class.first scoped(left_column_name => { '$lte' => left }, right_column_name => { '$gte' => right })
    end

    # Returns the array of all parents and self
    def self_and_ancestors
      base_class.all scoped(left_column_name => { '$lte' => left }, right_column_name => { '$gte' => right })
    end

    # Returns an array of all parents
    def ancestors
      without_self self_and_ancestors
    end

    # Returns the array of all children of the parent, including self
    def self_and_siblings
      base_class.all scoped(parent_column_name => _parent_id)
    end

    # Returns the array of all children of the parent, except self
    def siblings
      without_self self_and_siblings
    end

    # Returns a set of all of its nested children which do not have children  
    # def leaves
    #   descendants.scoped :conditions => "#{self.class.collection_name}.#{quoted_right_column_name} - #{self.class.collection_name}.#{quoted_left_column_name} = 1"
    # end    

    # Returns the level of this object in the tree
    # root level is 0
    def level
      _parent_id.nil? ? 0 : ancestors.count
    end

    # Returns a set of itself and all of its nested children
    def self_and_descendants
      base_class.all scoped(left_column_name => { '$gte' => left }, right_column_name => { '$lte' => right })
    end

    # Returns a set of all of its children and nested children
    def descendants
      without_self self_and_descendants
    end

    def is_descendant_of?(other)
      other.left < self.left && self.left < other.right && same_scope?(other)
    end
    
    def is_or_is_descendant_of?(other)
      other.left <= self.left && self.left < other.right && same_scope?(other)
    end

    def is_ancestor_of?(other)
      self.left < other.left && other.left < self.right && same_scope?(other)
    end
    
    def is_or_is_ancestor_of?(other)
      self.left <= other.left && other.left < self.right && same_scope?(other)
    end
    
    # Check if other model is in the same scope
    def same_scope?(other)
      Array(acts_as_nested_set_options[:scope]).all? do |attr|
        self.send(attr) == other.send(attr)
      end
    end

    # Find the first sibling to the left
    def left_sibling
      base_class.first scoped(parent_column_name => _parent_id, left_column_name => { '$lt' => left }, :order => "#{left_column_name} DESC")
    end

    # Find the first sibling to the right
    def right_sibling
      base_class.first scoped(parent_column_name => _parent_id, left_column_name => { '$gt' => right }, :order => "#{left_column_name}")
    end

    # Shorthand method for finding the left sibling and moving to the left of it.
    def move_left
      move_to_left_of left_sibling
    end

    # Shorthand method for finding the right sibling and moving to the right of it.
    def move_right
      move_to_right_of right_sibling
    end

    # Move the node to the left of another node (you can pass id only)
    def move_to_left_of(node)
      move_to node, :left
    end

    # Move the node to the left of another node (you can pass id only)
    def move_to_right_of(node)
      move_to node, :right
    end

    # Move the node to the child of another node (you can pass id only)
    def move_to_child_of(node)
      move_to node, :child
    end
    
    # Move the node to root nodes
    def move_to_root
      move_to nil, :root
    end
    
    def move_possible?(target)
      self != target && # Can't target self
      same_scope?(target) && # can't be in different scopes
      # !(left..right).include?(target.left..target.right) # this needs tested more
      # detect impossible move
      !((left <= target.left && right >= target.left) or (left <= target.right && right >= target.right))
    end
    
    def to_text
      self_and_descendants.map do |node|
        "#{'*'*(node.level+1)} #{node.id} #{node.to_s} (#{node._parent_id}, #{node.left}, #{node.right})"
      end.join("\n")
    end
    
  protected
    def without_self(set)
      set.reject { |node| node.id == id }
    end
    
    # All nested set queries should use this nested_set_scope, which performs finds on
    # the base ActiveRecord class, using the :scope declared in the acts_as_nested_set
    # declaration.
    def nested_set_scope
      raise "called nested_set_scope"
      options = {:order => quoted_left_column_name}
      scopes = Array(acts_as_nested_set_options[:scope])
      options[:conditions] = scopes.inject({}) do |conditions,attr|
        conditions.merge attr => self[attr]
      end unless scopes.empty?
      self.class.base_class.scoped options
    end
    
    def store_new_parent
      unless @skip_nested_set_callbacks
        @move_to_new_parent_id = send("#{parent_column_name}_changed?") ? _parent_id : false
      end
      true # force callback to return true
    end
    
    def move_to_new_parent
      unless @skip_nested_set_callbacks
        if @move_to_new_parent_id.nil?
          move_to_root
        elsif @move_to_new_parent_id
          move_to_child_of(@move_to_new_parent_id)
        end
      end
    end
    
    # on creation, set automatically lft and rgt to the end of the tree
    def set_default_left_and_right
      unless @skip_nested_set_callbacks
        maxright = base_class.first(scoped(:order => "#{right_column_name} DESC")).try(right_column_name) || 0
        # adds the new node to the right of all existing nodes
        self[left_column_name] = maxright + 1
        self[right_column_name] = maxright + 2
      end
    end
  
    # Prunes a branch off of the tree, shifting all of the elements on the right
    # back to the left so the counts still work.
    def destroy_descendants
      return if right.nil? || left.nil? || skip_before_destroy
      
      if acts_as_nested_set_options[:dependent] == :destroy
        descendants.each do |model|
          model.skip_before_destroy = true
          model.destroy
        end
      else
        base_class.delete_all scoped(left_column_name => { '$gt' => left }, right_column_name => { '$lt' => right })
      end
      
      # update lefts and rights for remaining nodes
      diff = right - left + 1
      base_class.all(scoped(left_column_name => { '$gt' => right })).each do |node|
        node.update_attributes left_column_name => node.left - diff
      end
      base_class.all(scoped(right_column_name => { '$gt' => right })).each do |node|
        node.update_attributes right_column_name => node.right - diff
      end
      
      # Don't allow multiple calls to destroy to corrupt the set
      self.skip_before_destroy = true
    end
    
    # reload left, right, and parent
    def reload_nested_set
      doc = self.class.find(_id)
      self.class.associations.each { |name, assoc| send(name).reset if respond_to?(name) }
      [ left_column_name, right_column_name, parent_column_name ].each do |column|
        send :"#{column}=", doc.send(column.to_sym)
      end
      self
    end
    
    def move_to(target, position)
      raise ArgumentError, "You cannot move a new node" if self.new_record?
      return if run_callbacks(:before_move) == false

      if target.is_a? base_class
        target.reload_nested_set
      elsif position != :root
        # load object if node is not an object
        target = base_class.find(target, scoped)
      end
      self.reload_nested_set
    
      unless position == :root || move_possible?(target)
        raise ArgumentError, "Impossible move, target node cannot be inside moved tree."
      end
      
      bound = case position
        when :child;  target.send(right_column_name)
        when :left;   target.send(left_column_name)
        when :right;  target.send(right_column_name) + 1
        when :root;   1
        else raise ArgumentError, "Position should be :child, :left, :right or :root ('#{position}' received)."
      end
    
      if bound > self.send(right_column_name)
        bound = bound - 1
        other_bound = self.send(right_column_name) + 1
      else
        other_bound = self.send(left_column_name) - 1
      end

      # there would be no change
      return if bound == self.send(right_column_name) || bound == self.send(left_column_name)
    
      # we have defined the boundaries of two non-overlapping intervals, 
      # so sorting puts both the intervals and their boundaries in order
      a, b, c, d = [self.send(left_column_name), self.send(right_column_name), bound, other_bound].sort

      new_parent = case position
        when :child;  target.id
        when :root;   nil
        else          target.send(parent_column_name)
      end

      base_class.all(scoped(:fields => [ left_column_name, right_column_name, parent_column_name ])).each do |node|
        if (a..b).include? node.left
          node.update_column left_column_name, node.left + d - b
        elsif (c..d).include? node.left
          node.update_column left_column_name, node.left + a - c
        end
        
        if (a..b).include? node.right
          node.update_column right_column_name, node.right + d - b
        elsif (c..d).include? node.right
          node.update_column right_column_name, node.right + a - c
        end
        node.update_column parent_column_name, new_parent if self.id == node.id
      end

      target.reload_nested_set if target
      self.reload_nested_set
      run_callbacks(:after_move)
    end
    
    def without_nested_set_callbacks(&block)
      old_value, @skip_nested_set_callbacks = @skip_nested_set_callbacks || false, true
      yield self
      @skip_nested_set_callbacks = old_value
    end
    
    def update_column(name, value)
      base_class.collection.update({ :_id => id }, { '$set' => { name => value } })
    end
  end
end