f# Sigils - new language

Some chicken scratch ideas..

## Overview

The main goal over all else is to create a language with NO keywords. Only symbols. Why? ¯\_(ツ)_/¯
I was playing with a simple esoteric language in which I was limiting myself to an instruction set of 16 commands, which I used consecutive ascii values starting with the space.

As I was writing example programs, I was enjoying the quick and simple command structure; it was a fun challenge to map commands to the symbols and have them be memorable.

This project is an exercise to make a marginally more useful language that still has that core idea of language keywords being simple symbols

Other aspects, such as heavy usage of the stack, I’m fond of but aren’t a core principle… so I could see those changing as I work on the design and implementation.

Every keyword of the language is a single (or double?) character symbol.
Everything is prefix oriented. Some things may *look* infix because of the use of the stack.

## Functions

### Definition
```
{:name
	# body
}>1
```
(The >1 means it returns a single value to the stack)

If named with a symbol, it will exist outside the local scope with that name (classes/namespaces tbd). If named without a colon it will be local. (Really? Is that needed, since we could write it to a variable instead after defining it.)

If a function is declared with a symbol name, it will escape local scope (I *think*?)
```
{local_function … }
{:global_function .. }
```

### Running
```
!name
```

### Arguments
Passing arguments to a function involves constructing an array or hash map and then reading that into the function at the beginning.
```
{:hello
  ->name
  ”Hello, ${name}.” !print
}>0
```

Running this:
```
“Eric” !hello
```

### Returning
The stack is used for passing values around. The state of the stack for each function is thrown away by default unless the definition says to keep anything (thought: maybe we keep the stack, see crazy example below). This is done with the > at the end, and a number specifying how many stack values to retain (ie: write back to the parent stack).

If [] is written instead of a number, the stack is converted into an array. (Not sure how to do hash maps)

(Thoughts: this spreads out the function signature, which may or may not be problematic.)

### Multiple Arguments

Subtly slipped into these example is calling an anonymous function.

Stack style
```
“Eric”
“Baur”
!{
  ->firstName
  ->lastName
  ”Hello, ${firstName} ${lastName}.”
  !print
}
```

Array style
```
“Eric”, “Baur”
!{
  ->[firstName, lastName]
  ”Hello, ${firstName} ${lastName}.”
  !print
}
```

(If comma binds tighter than other operations we wouldn’t need the [])
```
“Eric”, “Baur”
!{
  ->firstName, lastName
  ”Hello, ${firstName} ${lastName}.”
  !print
}
```

Hash maps?


## Working with the Stack

All values get written to the stack. Read from stack:
```
->var1
```

So, adding two numbers and storing the result might be:
```
3 + 5 -> eight

3         # put three on stack
+ 5       # add five to stack
-> eight  # put stack into var named “eight”
```

(Thoughts: what about using <- to read from *after* the method call (ie: allows the parser to wait until another thing is written to the stack before it runs the method. Otherwise, how does 3+5 work?)

```
{+
```
```
  -> x
  <- y
  //add stuff
```
```
}>1

```
```
3 + 5 -> ans

//VS
```
```

{+
  -> x
```
```
  -> y
  //add stuff
```
```
}>1

```
```
3 5 + -> ans

```
```

```

### Peeking
Using a ? allows you to use a stack value for another operation without consuming it (the default for most operations).

For example, you could read the same value twice with:
```
?->copy1
->copy2
```

### Random Access
Use the @ symbol to grab a stack value at a different location than the top. This also does not consume a value.
```
@0->var1    # top of stack
@1->var2    # second from top
@-1-> var  # last value in stack
@loc        # use variable to access
```

(Thoughts: might not be necessary to have ? and @, or @ consumes unless also ?… like @0?->var1. Also, what does a “bare” @0 do? Does it duplicate, or would @0? duplicate?)

## Strings

Strings are denoted by quotes or starting with a $, and the first character following them determines the delimiters (do I really want to support character delimiters?). A : denotes a symbol. Symbols can only be delimited by non-alphanumeric characters or no delimiter means a space will terminate the symbol.

If $ appears in a string it “switches” back to interpreting as code, allowing for variable interpolation.
```
”this is a string”
${this is also a string (that can’t have an un-escaped \{ in it)}
“This is a string with a ${variable} in it”
“Another string with a $(variable)”

:symbol
:”symbol with spaces”
```

Using “ or ‘ requires the string be on a single line, using a paired delimited (), {}, [] also allows it to be multi-line.

## Arrays

The unassuming comma is the array constructor.
```
1, 2, 3   # array of 3 numbers
# or…
1  # put 1 on the stack
,2 # combine existing stack (value) with 2
,2 # combine existing stack (array) with 3
```

This means an array with one value is (assuming nothing on the stack)
```
,1
```

Empty array is just []
So the above example could more safely be done as:
```
[],1
```

(I’m not sure i like this… probably don’t need to avoid [] and just have the comma be a convenience)

Note that the [] are not array delimiters, the pair together signifies an empty array, values cannot be put between them. (For now…)

Arrays (and maybe hash maps?) are a common pattern to calling functions; but not strictly required. See Functions for an example.

## Looping

Loops are denoted using parenthesis. The variable following the open parenthesis will be the initialized, for example to loop over an array of values, you might do something like this:
```
(array -> element
  # body of loop
)
```
In this case, the array element is placed on the stack and then the -> reads in the value to a variable. By default loops do not return a value, but they can with a number on the close paren. That number tells it how many values to retain on the stack for the next loop (or at the end). Using this you can create a reduce style loop:
```
(array -> element -> collector
  collector + element
)>1 -> total
```

Or, since collector just reads from the stack, and then immediately uses it, you can shorten to:
```
(array -> element
  + element
)>1 -> total
```

Looking at other uses, like a map, you can have it leave an array on the stack. This example shows how we might double all the array elements (syntax uncertain/TBD):
```
(source_array * 2)>[] -> doubles
```
(This example also shortens the loop by using the first stack value as an unnamed value.)

Thoughts: does this mean we can loop over the existing stack with:
```
(-> element
```

## Crazy Examples

Stack values for input and returns

Q: Can a method return more stack values than it uses?

```
“Foo” “Bar” !{
  ->param1
```
```
}>1
```

Would this return “Foo”?

# Even more chicken scratchy than above….
Wrote these down after thinking about it going to sleep.

## Ranges / Iterators?
An ellipsis creates an iterators over a range.
1…10 # count from 1 to 10

… keeps internal state and returns the next value (maybe until a ;?)

## Flow Control
(? condition ?){ true_statements }:{ false_statements }

## Imports
A • for imports!
