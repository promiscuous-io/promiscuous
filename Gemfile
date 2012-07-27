source :rubygems
gemspec

ENV['MONGOID_VERSION'] ||= "3.0"

group :test do
  gem 'rake'
  gem 'mongoid', "~> #{ENV['MONGOID_VERSION']}"
  gem 'rspec'
  gem 'mocha', :require => false
end
