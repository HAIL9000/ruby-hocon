# encoding: utf-8

require 'hocon'
require 'spec_helper'
require 'rspec'
require 'hocon/impl/config_reference'
require 'hocon/impl/substitution_expression'

module TestUtils
  Tokens = Hocon::Impl::Tokens
  ConfigInt = Hocon::Impl::ConfigInt
  ConfigFloat = Hocon::Impl::ConfigFloat
  ConfigString = Hocon::Impl::ConfigString
  ConfigNull = Hocon::Impl::ConfigNull
  ConfigBoolean = Hocon::Impl::ConfigBoolean
  ConfigReference = Hocon::Impl::ConfigReference
  SubstitutionExpression = Hocon::Impl::SubstitutionExpression
  ConfigConcatenation = Hocon::Impl::ConfigConcatenation
  Path = Hocon::Impl::Path
  EOF = Hocon::Impl::TokenType::EOF

  include RSpec::Matchers

  def self.intercept(exception_type, & block)
    thrown = nil
    result = nil
    begin
      result = block.call
    rescue => e
      if e.is_a?(exception_type)
        thrown = e
      else
        raise ArgumentError, "Expected exception #{exception_type} was not thrown, got #{e}\n#{e.backtrace.join("\n")}"
      end
    end
    if thrown.nil?
      raise ArgumentError, "Expected exception #{exception_type} was not thrown, no exception was thrown and got result #{result}"
    end
    thrown
  end

  class ParseTest

    def self.from_s(test)
      ParseTest.new(false, false, test)
    end

    def self.from_pair(lift_behavior_unexpected, test)
      ParseTest.new(lift_behavior_unexpected, false, test)
    end

    def initialize(lift_behavior_unexpected, whitespace_matters, test)
      @lift_behavior_unexpected = lift_behavior_unexpected
      @whitespace_matters = whitespace_matters
      @test = test
    end
    attr_reader :test

    def lift_behavior_unexpected?
      @lift_behavior_unexpected
    end

    def whitespace_matters?
      @whitespace_matters
    end
  end


# note: it's important to put {} or [] at the root if you
# want to test "invalidity reasons" other than "wrong root"
  InvalidJsonInvalidConf = [
      ParseTest.from_s("{"),
      ParseTest.from_s("}"),
      ParseTest.from_s("["),
      ParseTest.from_s("]"),
      ParseTest.from_s(","),
      ParseTest.from_pair(true, "10"), # value not in array or object, lift-json now allows this
      ParseTest.from_pair(true, "\"foo\""), # value not in array or object, lift-json allows it
      ParseTest.from_s(")\""), # single quote by itself
      ParseTest.from_pair(true, "[,]"), # array with just a comma in it; lift is OK with this
      ParseTest.from_pair(true, "[,,]"), # array with just two commas in it; lift is cool with this too
      ParseTest.from_pair(true, "[1,2,,]"), # array with two trailing commas
      ParseTest.from_pair(true, "[,1,2]"), # array with initial comma
      ParseTest.from_pair(true, "{ , }"), # object with just a comma in it
      ParseTest.from_pair(true, "{ , , }"), # object with just two commas in it
      ParseTest.from_s("{ 1,2 }"), # object with single values not key-value pair
      ParseTest.from_pair(true, '{ , "foo" : 10 }'), # object starts with comma
      ParseTest.from_pair(true, "{ \"foo\" : 10 ,, }"), # object has two trailing commas
      ParseTest.from_s(") \"a\" : 10 ,, "), # two trailing commas for braceless root object
      ParseTest.from_s("{ \"foo\" : }"), # no value in object
      ParseTest.from_s("{ : 10 }"), # no key in object
      ParseTest.from_pair(true, " \"foo\" : "), # no value in object with no braces; lift-json thinks this is acceptable
      ParseTest.from_pair(true, " : 10 "), # no key in object with no braces; lift-json is cool with this too
      ParseTest.from_s(') "foo" : 10 } '), # close brace but no open
      ParseTest.from_s(") \"foo\" : 10 } "), # close brace but no open
      ParseTest.from_s(") \"foo\" : 10 [ "), # no-braces object with trailing gunk
      ParseTest.from_s("{ \"foo\" }"), # no value or colon
      ParseTest.from_s("{ \"a\" : [ }"), # [ is not a valid value
      ParseTest.from_s("{ \"foo\" : 10, true }"), # non-key after comma
      ParseTest.from_s("{ foo \n bar : 10 }"), # newline in the middle of the unquoted key
      ParseTest.from_s("[ 1, \\"), # ends with backslash
      # these two problems are ignored by the lift tokenizer
      ParseTest.from_s("[:\"foo\", \"bar\"]"), # colon in an array; lift doesn't throw (tokenizer erases it)
      ParseTest.from_s("[\"foo\" : \"bar\"]"), # colon in an array another way, lift ignores (tokenizer erases it)
      ParseTest.from_s("[ \"hello ]"), # unterminated string
      ParseTest.from_pair(true, "{ \"foo\" , true }"), # comma instead of colon, lift is fine with this
      ParseTest.from_pair(true, "{ \"foo\" : true \"bar\" : false }"), # missing comma between fields, lift fine with this
      ParseTest.from_s("[ 10, }]"), # array with } as an element
      ParseTest.from_s("[ 10, {]"), # array with { as an element
      ParseTest.from_s("{}x"), # trailing invalid token after the root object
      ParseTest.from_s("[]x"), # trailing invalid token after the root array
      ParseTest.from_pair(true, "{}{}"), # trailing token after the root object - lift OK with it
      ParseTest.from_pair(true, "{}true"), # trailing token after the root object; lift ignores the {}
      ParseTest.from_pair(true, "[]{}"), # trailing valid token after the root array
      ParseTest.from_pair(true, "[]true"), # trailing valid token after the root array, lift ignores the []
      ParseTest.from_s("[${]"), # unclosed substitution
      ParseTest.from_s("[$]"), # '$' by itself
      ParseTest.from_s("[$  ]"), # '$' by itself with spaces after
      ParseTest.from_s("[${}]"), # empty substitution (no path)
      ParseTest.from_s("[${?}]"), # no path with ? substitution
      ParseTest.new(false, true, "[${ ?foo}]"), # space before ? not allowed
      ParseTest.from_s(%q|{ "a" : [1,2], "b" : y${a}z }|), # trying to interpolate an array in a string
      ParseTest.from_s(%q|{ "a" : { "c" : 2 }, "b" : y${a}z }|), # trying to interpolate an object in a string
      ParseTest.from_s(%q|{ "a" : ${a} }|), # simple cycle
      ParseTest.from_s(%q|[ { "a" : 2, "b" : ${${a}} } ]|), # nested substitution
      ParseTest.from_s("[ = ]"), # = is not a valid token in unquoted text
      ParseTest.from_s("[ + ]"),
      ParseTest.from_s("[ # ]"),
      ParseTest.from_s("[ ` ]"),
      ParseTest.from_s("[ ^ ]"),
      ParseTest.from_s("[ ? ]"),
      ParseTest.from_s("[ ! ]"),
      ParseTest.from_s("[ @ ]"),
      ParseTest.from_s("[ * ]"),
      ParseTest.from_s("[ & ]"),
      ParseTest.from_s("[ \\ ]"),
      ParseTest.from_s("+="),
      ParseTest.from_s("[ += ]"),
      ParseTest.from_s("+= 10"),
      ParseTest.from_s("10 +="),
      ParseTest.from_s("[ 10e+3e ]"), # "+" not allowed in unquoted strings, and not a valid number
      ParseTest.from_pair(true, "[ \"foo\nbar\" ]"), # unescaped newline in quoted string, lift doesn't care
      ParseTest.from_s("[ # comment ]"),
      ParseTest.from_s("${ #comment }"),
      ParseTest.from_s("[ // comment ]"),
      ParseTest.from_s("${ // comment }"),
      ParseTest.from_s("{ include \"bar\" : 10 }"), # include with a value after it
      ParseTest.from_s("{ include foo }"), # include with unquoted string
      ParseTest.from_s("{ include : { \"a\" : 1 } }"), # include used as unquoted key
      ParseTest.from_s("a="), # no value
      ParseTest.from_s("a:"), # no value with colon
      ParseTest.from_s("a= "), # no value with whitespace after
      ParseTest.from_s("a.b="), # no value with path
      ParseTest.from_s("{ a= }"), # no value inside braces
      ParseTest.from_s("{ a: }") # no value with colon inside braces
  ]

  def self.add_offending_json_to_exception(parser_name, s, & block)
    begin
      block.call
    rescue => e
      tokens =
          begin
            "tokens: " + TestUtils.tokenize_as_list(s).join("\n")
          rescue => tokenize_ex
            "tokenizer failed: #{tokenize_ex}\n#{tokenize_ex.backtrace.join("\n")}"
          end
      raise ArgumentError, "#{parser_name} parser did wrong thing on '#{s}', #{tokens}; error: #{e}\n#{e.backtrace.join("\n")}"
    end
  end

  def self.whitespace_variations(tests, valid_in_lift)
    variations = [
        Proc.new { |s| s }, # identity
        Proc.new { |s| " " + s },
        Proc.new { |s| s + " " },
        Proc.new { |s| " " + s + " " },
        Proc.new { |s| s.gsub(" ", "") }, # this would break with whitespace in a key or value
        Proc.new { |s| s.gsub(":", " : ") }, # could break with : in a key or value
        Proc.new { |s| s.gsub(",", " , ") }, # could break with , in a key or value
    ]
    tests.map { |t|
      if t.whitespace_matters?
        t
      else
        with_no_ascii =
            if t.test.include?(" ")
              [ParseTest.from_pair(valid_in_lift,
                                   t.test.gsub(" ", "\u2003"))] # 2003 = em space, to test non-ascii whitespace
            else
              []
            end

        with_no_ascii << variations.reduce([]) { |acc, v|
          acc << ParseTest.from_pair(t.lift_behavior_unexpected?, v.call(t.test))
          acc
        }
      end
    }.flatten
  end


  ##################
  # Tokenizer Functions
  ##################
  def self.wrap_tokens(token_list)
    # Wraps token_list in START and EOF tokens
    [Tokens::START] + token_list + [Tokens::EOF]
  end

  def self.tokenize(config_origin, input)
    Hocon::Impl::Tokenizer.tokenize(config_origin, input, Hocon::ConfigSyntax::CONF)
  end

  def self.tokenize_from_s(s)
    tokenize(Hocon::Impl::SimpleConfigOrigin.new_simple("anonymous Reader"),
             StringIO.new(s))
  end

  def self.tokenize_as_list(input_string)
    token_iterator = tokenize_from_s(input_string)

    token_iterator.to_list
  end

  def self.tokenize_as_string(input_string)
    Hocon::Impl::Tokenizer.render(tokenize_from_s(input_string))
  end

  def self.fake_origin
    Hocon::Impl::SimpleConfigOrigin.new_simple("fake origin")
  end

  def self.token_line(line_number)
    Tokens.new_line(fake_origin.with_line_number(line_number))
  end

  def self.token_true
    Tokens.new_boolean(fake_origin, true)
  end

  def self.token_false
    Tokens.new_boolean(fake_origin, false)
  end

  def self.token_null
    Tokens.new_null(fake_origin)
  end

  def self.token_unquoted(value)
    Tokens.new_unquoted_text(fake_origin, value)
  end

  def self.token_comment_double_slash(value)
    Tokens.new_comment_double_slash(fake_origin, value)
  end

  def self.token_comment_hash(value)
    Tokens.new_comment_hash(fake_origin, value)
  end

  def self.token_whitespace(value)
    Tokens.new_ignored_whitespace(fake_origin, value)
  end

  def self.token_string(value)
    Tokens.new_string(fake_origin, value, value)
  end

  def self.token_float(value)
    Tokens.new_float(fake_origin, value, nil)
  end

  def self.token_int(value)
    Tokens.new_int(fake_origin, value, nil)
  end

  def self.token_maybe_optional_substitution(optional, token_list)
    Tokens.new_substitution(fake_origin, optional, token_list)
  end

  def self.token_substitution(*token_list)
    token_maybe_optional_substitution(false, token_list)
  end

  def self.token_optional_substitution(*token_list)
    token_maybe_optional_substitution(true, token_list)
  end

  def self.token_key_substitution(value)
    token_substitution(token_string(value))
  end

  def self.parse_config(s)
    options = Hocon::ConfigParseOptions.defaults
                  .set_origin_description("test string")
                  .set_syntax(Hocon::ConfigSyntax::CONF)
    Hocon::ConfigFactory.parse_string(s, options)
  end

  ##################
  # ConfigValue helpers
  ##################
  def self.int_value(value)
    ConfigInt.new(fake_origin, value, nil)
  end

  def self.float_value(value)
    ConfigFloat.new(fake_origin, value, nil)
  end

  def self.string_value(value)
    ConfigString.new(fake_origin, value)
  end

  def self.null_value
    ConfigNull.new(fake_origin)
  end

  def self.bool_value(value)
    ConfigBoolean.new(fake_origin, value)
  end

  def self.config_map(input_map)
    # Turns {String: Int} maps into {String: ConfigInt} maps
    Hash[ input_map.map { |k, v| [k, int_value(v)] } ]
  end

  def self.subst(ref, optional = false)
    path = Path.new_path(ref)
    ConfigReference.new(fake_origin, SubstitutionExpression.new(path, optional))
  end

  def self.subst_in_string(ref, optional = false)
    pieces = [string_value("start<"), subst(ref, optional), string_value(">end")]
    ConfigConcatenation.new(fake_origin, pieces)
  end

  def self.parse_config(config_string)
    options = Hocon::ConfigParseOptions.defaults
    options.origin_description = "test string"
    options.syntax = Hocon::ConfigSyntax::CONF

    Hocon::ConfigFactory.parse_string(config_string, options)
  end

  ##################
  # Token Functions
  ##################
  class NotEqualToAnythingElse
    def ==(other)
      other.is_a? NotEqualToAnythingElse
    end

    def hash
      971
    end
  end

  ##################
  # Path Functions
  ##################
  def self.path(*elements)
    # this is importantly NOT using Path.newPath, which relies on
    # the parser; in the test suite we are often testing the parser,
    # so we don't want to use the parser to build the expected result.
    Path.from_string_list(elements)
  end

  ##################
  # RSpec Tests
  ##################
  def self.check_equal_objects(first_object, second_object)
    it "should find the two objects to be equal" do
      not_equal_to_anything_else = TestUtils::NotEqualToAnythingElse.new

      # Equality
      expect(first_object).to eq(second_object)
      expect(second_object).to eq(first_object)

      # Hashes
      expect(first_object.hash).to eq(second_object.hash)

      # Other random object
      expect(first_object).not_to eq(not_equal_to_anything_else)
      expect(not_equal_to_anything_else).not_to eq(first_object)

      expect(second_object).not_to eq(not_equal_to_anything_else)
      expect(not_equal_to_anything_else).not_to eq(second_object)
    end
  end

  def self.check_not_equal_objects(first_object, second_object)

    it "should find the two objects to be not equal" do
      not_equal_to_anything_else = TestUtils::NotEqualToAnythingElse.new

      # Equality
      expect(first_object).not_to eq(second_object)
      expect(second_object).not_to eq(first_object)

      # Hashes
      # hashcode inequality isn't guaranteed, but
      # as long as it happens to work it might
      # detect a bug (if hashcodes are equal,
      # check if it's due to a bug or correct
      # before you remove this)
      expect(first_object.hash).not_to eq(second_object.hash)

      # Other random object
      expect(first_object).not_to eq(not_equal_to_anything_else)
      expect(not_equal_to_anything_else).not_to eq(first_object)

      expect(second_object).not_to eq(not_equal_to_anything_else)
      expect(not_equal_to_anything_else).not_to eq(second_object)
    end
  end
end


##################
# RSpec Shared Examples
##################

# Examples for comparing an object that won't equal anything but itself
# Used in the object_equality examples below
shared_examples_for "not_equal_to_other_random_thing" do
  let(:not_equal_to_anything_else) { TestUtils::NotEqualToAnythingElse.new }

  it "should find the first object not equal to a random other thing" do
    expect(first_object).not_to eq(not_equal_to_anything_else)
    expect(not_equal_to_anything_else).not_to eq(first_object)
  end

  it "should find the second object not equal to a random other thing" do
    expect(second_object).not_to eq(not_equal_to_anything_else)
    expect(not_equal_to_anything_else).not_to eq(second_object)
  end
end

# Examples for making sure two objects are equal
shared_examples_for "object_equality" do

  it "should find the first object to be equal to the second object" do
    expect(first_object).to eq(second_object)
  end

  it "should find the second object to be equal to the first object" do
    expect(second_object).to eq(first_object)
  end

  it "should find the hash codes of the two objects to be equal" do
    expect(first_object.hash).to eq(second_object.hash)
  end

  include_examples "not_equal_to_other_random_thing"
end

# Examples for making sure two objects are not equal
shared_examples_for "object_inequality" do

  it "should find the first object to not be equal to the second object" do
    expect(first_object).not_to eq(second_object)
  end

  it "should find the second object to not be equal to the first object" do
    expect(second_object).not_to eq(first_object)
  end

  it "should find the hash codes of the two objects to not be equal" do
    # hashcode inequality isn't guaranteed, but
    # as long as it happens to work it might
    # detect a bug (if hashcodes are equal,
    # check if it's due to a bug or correct
    # before you remove this)
    expect(first_object.hash).not_to eq(second_object.hash)
  end

  include_examples "not_equal_to_other_random_thing"
end


shared_examples_for "path_render_test" do
  it "should find the expected rendered text equal to the rendered path" do
    expect(path.render).to eq(expected)
  end

  it "should find the path equal to the parsed expected text" do
    expect(Hocon::Impl::Parser.parse_path(expected)).to eq(path)
  end

  it "should find the path equal to the parsed text that came from the rendered path" do
    expect(Hocon::Impl::Parser.parse_path(path.render)).to eq(path)
  end
end