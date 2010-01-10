class Category
  include MongoMapper::Document
  
  acts_as_nested_set
  
  key :organization_id, String
  
  def to_s
    name
  end
  
  def recurse &block
    block.call self, lambda{
      self.children.each do |child|
        child.recurse &block
      end
    }
  end
end