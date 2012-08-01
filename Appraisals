appraise 'mongoid2' do
  gem 'mongoid', "~> 2.0"
  gem 'bson_ext'
end

# Mongoid 3 only supports ruby 1.9.3+
if Gem::Version.new(RUBY_VERSION.dup) >= Gem::Version.new('1.9.3')
  appraise 'mongoid3' do
    gem 'mongoid', "~> 3.0"
  end
end
