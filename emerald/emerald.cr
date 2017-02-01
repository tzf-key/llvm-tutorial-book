require "./types"
require "./error"
require "./token"
require "./nodes/node.cr"
require "./nodes/*"
require "./lexer"
require "./verifier"
require "./parser"
require "./state"
require "./close_statements"

require "llvm"

class EmeraldProgram
  getter input_code, token_array, ast, output, delimiters, state, mod, builder, options, verifier, main : LLVM::BasicBlock
  getter! lexer, parser, func : LLVM::Function

  def initialize(@input_code : String, @test_mode : Bool = false)
    @options = {
      "color"             => true,
      "supress"           => false,
      "printTokens"       => false,
      "printAST"          => false,
      "printResolutions"  => false,
      "printInstructions" => false,
      "printOutput"       => false,
      "filename"          => "",
    }
    @token_array = [] of Token
    @ast = [] of Node
    @output = ""
    @verifier = Verifier.new
    @mod = LLVM::Module.new("Emerald")
    @func = mod.functions.add "main", ([] of LLVM::Type), LLVM::Int32
    @main = func.basic_blocks.append "main_body"
    @builder = LLVM::Builder.new
    @state = ProgramState.new builder, mod, main
  end

  def initialize(@options : Hash(String, (String | Bool)), @test_mode : Bool = false)
    @input_code = File.read(@options["filename"].as(String))
    @token_array = [] of Token
    @ast = [] of Node
    @output = ""
    @verifier = Verifier.new
    @mod = LLVM::Module.new("Emerald")
    @func = mod.functions.add "main", ([] of LLVM::Type), LLVM::Int32
    @main = func.basic_blocks.append "main_body"
    @builder = LLVM::Builder.new
    @state = ProgramState.new builder, mod, main
  end

  def lex : Nil
    @lexer = Lexer.new input_code
    @token_array = lexer.lex
    if options["printTokens"]
      puts options["color"] ? "\033[032mTOKENS\033[039m" : "TOKENS"
      @token_array.each do |token|
        puts token.to_s
      end
      puts
    end
    begin
      verifier.verify_token_array @token_array
    rescue ex : EmeraldSyntaxException
      ex.full_error @input_code, @options["color"].as(Bool), @test_mode
    end
  end

  def parse : Nil
    @parser = Parser.new token_array
    begin
      @ast = parser.parse
    rescue ex : EmeraldSyntaxException
      ex.full_error @input_code, @options["color"].as(Bool), @test_mode
    end
  end

  def generate : Nil
    # Add debug values to state
    state.printAST = options["printAST"].as(Bool)
    state.printResolutions = options["printResolutions"].as(Bool)
    if state.printAST || state.printResolutions
      puts options["color"] ? "\033[032mAST / RESOLUTIONS\033[039m" : "AST / RESOLUTIONS"
    end

    # Walk nodes to resolve values and generate llvm ir
    begin
      @ast[0].walk state
      state.close_blocks
    rescue ex : EmeraldSyntaxException
      ex.full_error @input_code, @options["color"].as(Bool), @test_mode
    end

    if state.printAST || state.printResolutions
      puts
    end

    # Output LLVM IR to output.ll
    output
  end

  def output : String
    if !options["supress"]
      File.open("output.ll", "w") do |file|
        mod.to_s(file)
      end
    end
    if options["printOutput"]
      puts options["color"] ? "\033[032mOUTPUT\033[039m" : "OUTPUT"
      puts mod.to_s
      puts
    end
    @output = mod.to_s
  end

  def compile : Nil
    lex
    parse
    generate
  end
end

# input = "# I am a comment!
# four = 2 + 2
# puts four
# puts 10 < 6
# puts 11 != 10
# "

# program = EmeraldProgram.new input
# program.compile
# puts program.output
