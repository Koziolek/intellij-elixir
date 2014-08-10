package org.elixir_lang;

import com.intellij.lexer.FlexLexer;
import com.intellij.psi.tree.IElementType;
import org.elixir_lang.psi.ElixirTypes;
import com.intellij.psi.TokenType;

%%

%class ElixirFlexLexer
%implements FlexLexer
%unicode
%function advance
%type IElementType
%eof{  return;
%eof}

%{
  private java.util.Stack<Integer> lexicalStateStack = new java.util.Stack<Integer>();
%}

EOL = \n|\r|\r\n
WHITE_SPACE=[\ \t\f]

COMMENT = "#" [^\r\n]* {EOL}?

/*
 *   Integers
 */

// Include deprecated '0B' so it can be corrected
BINARY_INTEGER = "0" [Bb][01]+
// Include deprecated '0X' so it can be corrected
HEXADECIMAL_INTEGER = "0" [Xx][A-Fa-f0-9]+
// Include deprecated '0' so it can be corrected
OCTAL_INTEGER = "0" o?[0-7]+
INTEGER = {BINARY_INTEGER} | {HEXADECIMAL_INTEGER} | {OCTAL_INTEGER}

SINGLE_QUOTE = "'"
STRING = {SINGLE_QUOTE} ("\\'" | [^'])* {SINGLE_QUOTE}

DOUBLE_QUOTES = "\""
ESCAPED_DOUBLE_QUOTES = "\\" {DOUBLE_QUOTES}
ESCAPED_INTERPOLATION_START = "\\#"

INTERPOLATION_START = "#{"
INTERPOLATION_END = "}"

TRIPLE_DOUBLE_QUOTES = {DOUBLE_QUOTES}{3}

// state after YYINITIAL has taken care of any white space prefix
%state BODY
%state INTERPOLATED_STRING
%state INTERPOLATED_HEREDOC_END
%state INTERPOLATED_HEREDOC_LINE_BODY
%state INTERPOLATED_HEREDOC_LINE_START
%state INTERPOLATED_HEREDOC_START
%state INTERPOLATION

%%

<YYINITIAL> {
  /* Turn EOL and whitespace at beginning of file into a single {@link org.elixir_lang.psi.ElixirTypes.WHITE_SPACE} so
   * it is filtered out.
   */
  ({EOL}|{WHITE_SPACE})+      { yybegin(BODY); return TokenType.WHITE_SPACE; }

  {COMMENT}                   { yybegin(BODY); return ElixirTypes.COMMENT; }

  {INTEGER}                   { yybegin(BODY); return ElixirTypes.NUMBER; }

  {STRING}                    { yybegin(BODY); return ElixirTypes.STRING; }
  {TRIPLE_DOUBLE_QUOTES}      { // return to BODY instead of YYINITIAL since beginning of file error handling has
                                // fininished.
                                lexicalStateStack.push(BODY);
                                yybegin(INTERPOLATED_HEREDOC_START);
                                return ElixirTypes.TRIPLE_DOUBLE_QUOTES; }
  {DOUBLE_QUOTES}             { // return to BODY instead of YYINITIAL since beginning of file error handling has
                                // finished.
                                lexicalStateStack.push(BODY);
                                yybegin(INTERPOLATED_STRING);
                                return ElixirTypes.DOUBLE_QUOTES; }

  .                           { yybegin(BODY); return TokenType.BAD_CHARACTER; }
}

// Rules common to interpolated strings
<INTERPOLATED_STRING, INTERPOLATED_HEREDOC_LINE_BODY> {
  {INTERPOLATION_START}            { lexicalStateStack.push(yystate());
                                     yybegin(INTERPOLATION);
                                     return ElixirTypes.INTERPOLATION_START; }
  {ESCAPED_DOUBLE_QUOTES}          { return ElixirTypes.VALID_ESCAPE_SEQUENCE; }
  {ESCAPED_INTERPOLATION_START}    { return ElixirTypes.VALID_ESCAPE_SEQUENCE; }
}

// Rules that aren't common to INTERPOLATED_STRING and INTERPOLATED_HEREDOC_BODY
<INTERPOLATED_STRING> {
  {DOUBLE_QUOTES} { int previousLexicalState = lexicalStateStack.pop();
                    yybegin(previousLexicalState);
                    return ElixirTypes.DOUBLE_QUOTES; }
  {EOL}|.         { return ElixirTypes.STRING_FRAGMENT; }
}

// Rules that aren't dependent on detecting the end of INTERPOLATION can be shared between <BODY> and <INTERPOLATION>
<BODY, INTERPOLATION> {
  /* Compress {EOL} followed by more {EOL} or whitespace into {EOL} as only {EOL} is significant for Elixir's grammar.
   *
   * @see https://github.com/idavis/Innovatian.Idea.PowerShell/blob/80bbe5bbcb15f95d8b33f4a34b86acb6b65ac67e/src/lang/lexer/PowerShell.flex#L78
   * @see https://github.com/idavis/Innovatian.Idea.PowerShell/blob/80bbe5bbcb15f95d8b33f4a34b86acb6b65ac67e/src/lang/lexer/PowerShell.flex#L227
   */
  {EOL}({EOL}|{WHITE_SPACE})* { return ElixirTypes.EOL; }
  // This rule is only meant to match whitespace surrounded by other tokens as the above rule will handle blank lines.
  {WHITE_SPACE}+              { return TokenType.WHITE_SPACE; }

  {COMMENT}                   { return ElixirTypes.COMMENT; }

  {INTEGER}                   { return ElixirTypes.NUMBER; }

  {STRING}                    { return ElixirTypes.STRING; }
  {TRIPLE_DOUBLE_QUOTES}      { lexicalStateStack.push(yystate());
                                yybegin(INTERPOLATED_HEREDOC_START);
                                return ElixirTypes.TRIPLE_DOUBLE_QUOTES; }
  {DOUBLE_QUOTES}             { lexicalStateStack.push(yystate());
                                yybegin(INTERPOLATED_STRING);
                                return ElixirTypes.DOUBLE_QUOTES; }
}

// Only rules for <BODY>, but not <INTERPOLATION> go here.
// @note MUST be after <BODY, INTERPOLATION> so that BAD_CHARACTER doesn't match a single ' ' instead of {WHITE_SPACE}+.
<BODY> {
  .                           { return TokenType.BAD_CHARACTER; }
}

// Only rules for <INTERPOLATON>, but not <BODY> go here.
// @note must be after <BODY, INTERPOLATION> so that BAD_CHARACTER doesn't match a single ' ' instead of {WHITE_SPACE}+.
<INTERPOLATION> {
  {INTERPOLATION_END}         { int previousLexicalState = lexicalStateStack.pop();
                                yybegin(previousLexicalState);
                                return ElixirTypes.INTERPOLATION_END;
                              }

  .                           { return TokenType.BAD_CHARACTER; }
}

/* The start of a heredoc is unique as we want to handle the error condition of having characters other than a newline
   after the {TRIPLE_DOUBLE_QUOTES}:

       iex> """a
            ** (SyntaxError) iex:6: heredoc start must be followed by a new line after """ */
<INTERPOLATED_HEREDOC_START> {
  {EOL} { yybegin(INTERPOLATED_HEREDOC_LINE_START); return ElixirTypes.EOL; }
  .     { return TokenType.BAD_CHARACTER; }
}

<INTERPOLATED_HEREDOC_LINE_START> {
  /* TRIPLE_DOUBLE_QUOTES only end the heredoc when preceeded ONLY by whitespace on the line
     iex(7)>     """
     ...(7)>  hi
     ...(7)>   there"""
     ...(7)>
     ...(7)> """
     " hi\n  there\"\"\"\n\n" */
  {WHITE_SPACE}+ / {TRIPLE_DOUBLE_QUOTES} { yybegin(INTERPOLATED_HEREDOC_END); return TokenType.WHITE_SPACE; }
  {TRIPLE_DOUBLE_QUOTES} { yypushback(yylength()); yybegin(INTERPOLATED_HEREDOC_END); }
  .                      { yypushback(yylength()); yybegin(INTERPOLATED_HEREDOC_LINE_BODY); }
}

<INTERPOLATED_HEREDOC_LINE_BODY> {
  {EOL} { yybegin(INTERPOLATED_HEREDOC_LINE_START); return ElixirTypes.STRING_FRAGMENT; }
  .     { return ElixirTypes.STRING_FRAGMENT; }
}

<INTERPOLATED_HEREDOC_END> {
  {TRIPLE_DOUBLE_QUOTES} { int previousLexicalState = lexicalStateStack.pop();
                           yybegin(previousLexicalState);
                           return ElixirTypes.TRIPLE_DOUBLE_QUOTES; }
}