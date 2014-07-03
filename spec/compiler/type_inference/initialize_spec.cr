#!/usr/bin/env bin/crystal --run
require "../../spec_helper"

describe "Type inference: initialize" do
  it "types instance vars as nilable if doesn't invoke super in initialize" do
    node = parse("
      class Foo
        def initialize
          @baz = Baz.new
          @another = 1
        end
      end

      class Bar < Foo
        def initialize
          @another = 2
        end
      end

      class Baz
      end

      foo = Foo.new
      bar = Bar.new
    ")
    result = infer_type node
    mod = result.program
    foo = mod.types["Foo"] as NonGenericClassType
    foo.instance_vars["@baz"].type.should eq(mod.union_of(mod.nil, mod.types["Baz"]))
    foo.instance_vars["@another"].type.should eq(mod.int32)
  end

  it "types instance vars as nilable if doesn't invoke super in initialize with deep subclass" do
    node = parse("
      class Foo
        def initialize
          @baz = Baz.new
          @another = 1
        end
      end

      class Bar < Foo
        def initialize
          super
        end
      end

      class BarBar < Bar
        def initialize
          @another = 2
        end
      end

      class Baz
      end

      foo = Foo.new
      bar = Bar.new
    ")
    result = infer_type node
    mod = result.program
    foo = mod.types["Foo"] as NonGenericClassType
    foo.instance_vars["@baz"].type.should eq(mod.union_of(mod.nil, mod.types["Baz"]))
    foo.instance_vars["@another"].type.should eq(mod.int32)
  end

  it "types instance vars as nilable if doesn't invoke super with default arguments" do
    node = parse("
      class Foo
        def initialize
          @baz = Baz.new
          @another = 1
        end
      end

      class Bar < Foo
        def initialize(x = 1)
          super()
        end
      end

      class Baz
      end

      foo = Foo.new
      bar = Bar.new(1)
    ")
    result = infer_type node
    mod = result.program
    foo = mod.types["Foo"] as NonGenericClassType
    foo.instance_vars["@baz"].type.should eq(mod.types["Baz"])
    foo.instance_vars["@another"].type.should eq(mod.int32)
  end

  it "checks instance vars of included modules" do
    result = assert_type("
      module Lala
        def lala
          @x = 'a'
        end
      end

      class Foo
        include Lala
      end

      class Bar < Foo
        include Lala

        def initialize
          @x = 1
        end
      end

      b = Bar.new
      f = Foo.new
      f.lala
      ") { char }

    mod = result.program

    foo = mod.types["Foo"] as NonGenericClassType
    foo.instance_vars["@x"].type.should eq(mod.union_of(mod.nil, mod.int32, mod.char))

    bar = mod.types["Bar"] as NonGenericClassType
    bar.instance_vars.length.should eq(0)
  end

  it "errors when instance variable never assigned" do
    assert_error %(
      class Foo
        def foo
          @x.foo
        end
      end

      Foo.new.foo
      ), "(@x was never assigned a value)"
  end

  it "errors when instance variable never assigned" do
    assert_error %(
      class Foo
        def initialize
          @barbar = 1
        end
        def foo
          @barbaz.foo
        end
      end

      Foo.new.foo
      ), "(@barbaz was never assigned a value, did you mean @barbar?)"
  end

  it "types instance var as nilable if not always assigned" do
    assert_type(%(
      class Foo
        def initialize
          if 1 == 2
            @x = 1
          end
        end

        def x
          @x
        end
      end

      foo = Foo.new
      foo.x
      )) { nilable int32 }
  end

  it "types instance var as nilable if assigned in block" do
    assert_type(%(
      def bar
        yield if 1 == 2
      end

      class Foo
        def initialize
          bar do
            @x = 1
          end
        end

        def x
          @x
        end
      end

      foo = Foo.new
      foo.x
      )) { nilable int32 }
  end

  it "types instance var as not-nilable if assigned in block but previosly assigned" do
    assert_type(%(
      def bar
        yield if 1 == 2
      end

      class Foo
        def initialize
          @x = 1
          bar do
            @x = 2
          end
        end

        def x
          @x
        end
      end

      foo = Foo.new
      foo.x
      )) { int32 }
  end

  it "types instance var as nilable if used before assignment" do
    assert_type(%(
      class Foo
        def initialize
          x = @x
          @x = 1
        end

        def x
          @x
        end
      end

      foo = Foo.new
      foo.x
      )) { nilable int32 }
  end

  it "types instance var as non-nilable if calls super and super defines it" do
    assert_type(%(
      class Parent
        def initialize
          @x = 1
        end
      end

      class Foo < Parent
        def initialize
          super
          @x + 2
        end

        def x
          @x
        end
      end

      foo = Foo.new
      foo.x
      )) { int32 }
  end

  it "types instance var as non-nilable if calls super and super defines it, with one level of indirection" do
    assert_type(%(
      class Parent
        def initialize
          @x = 1
        end
      end

      class SubParent < Parent
      end

      class Foo < SubParent
        def initialize
          super
          @x + 2
        end

        def x
          @x
        end
      end

      foo = Foo.new
      foo.x
      )) { int32 }
  end

  it "doesn't type instance var as nilable if out" do
    assert_type(%(
      lib C
        fun foo(x : Int32*)
      end

      class Foo
        def initialize
          C.foo(out @x)
          @x + 2
        end

        def x
          @x
        end
      end

      foo = Foo.new
      foo.x
      )) { int32 }
  end

  it "types instance var as nilable if used after method call" do
    assert_type(%(
      class Foo
        def initialize
          foo
          @x = 1
        end

        def foo
        end

        def x
          @x
        end
      end

      foo = Foo.new
      foo.x
      )) { nilable int32 }
  end

  it "doesn't type instance var as nilable if used after global method call" do
    assert_type(%(
      def foo
      end

      class Foo
        def initialize
          foo
          @x = 1
        end

        def x
          @x
        end
      end

      foo = Foo.new
      foo.x
      )) { int32 }
  end

  it "doesn't type instance var as nilable if used after method call inside typeof" do
    assert_type(%(
      class Foo
        def initialize
          typeof(foo)
          @x = 1
        end

        def foo
          1
        end

        def x
          @x
        end
      end

      foo = Foo.new
      foo.x
      )) { int32 }
  end
end
