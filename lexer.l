%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include "parser.tab.h"

extern FILE *output_file;

static int bs_fprintf(FILE *stream, const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);

    va_list args_copy;
    va_copy(args_copy, args);
    int written = vfprintf(stream, fmt, args);

    if (stream == stderr) {
        FILE *out = output_file;
        int need_close = 0;
        if (!out) {
            out = fopen("output.txt", "a");
            if (out) need_close = 1;
        }
        if (out) {
            vfprintf(out, fmt, args_copy);
            fflush(out);
            if (need_close) fclose(out);
        }
    }

    va_end(args_copy);
    va_end(args);
    return written;
}

#define fprintf bs_fprintf

int line_num = 1;

/* Process escape sequences inside a string literal body (no surrounding quotes) */
static char *process_string(const char *s, int len) {
    char *result = malloc(len + 1);
    int j = 0, i;
    for (i = 0; i < len; i++) {
        if (s[i] == '\\' && i + 1 < len) {
            i++;
            switch (s[i]) {
                case 'n':  result[j++] = '\n'; break;
                case 't':  result[j++] = '\t'; break;
                case 'r':  result[j++] = '\r'; break;
                case '\\': result[j++] = '\\'; break;
                case '"':  result[j++] = '"';  break;
                case '\'': result[j++] = '\''; break;
                default:   result[j++] = '\\'; result[j++] = s[i]; break;
            }
        } else {
            result[j++] = s[i];
        }
    }
    result[j] = '\0';
    return result;
}
%}

%x ML_COMMENT

%%

"##"[^\n]*              { /* single-line comment: ignore until end of line */ }

"#*"                    { BEGIN(ML_COMMENT); }
<ML_COMMENT>"*#"        { BEGIN(INITIAL); }
<ML_COMMENT>\n          { line_num++; }
<ML_COMMENT>.           { /* ignore inside multi-line comment */ }
<ML_COMMENT><<EOF>>     {
                            fprintf(stderr, "Lexical Error: Unterminated multi-line comment at line %d\n", line_num);
                            exit(1);
                        }

[ \t\r]+                { /* whitespace: ignore */ }
\n                      { line_num++; }

"kaj"                   { return KAJ; }
"mukkho"                { return MUKKHO; }
"ferao"                 { return FERAO; }

"jodi"                  { return JODI; }
"naholeJodi"            { return NAHOLEJODI; }
"nahole"                { return NAHOLE; }

"ghurao"                { return GHURAO; }
"jotokkhon"             { return JOTOKKHON; }
"cholteThako"           { return CHOLTETHAKO; }
"thamo"                 { return THAMO; }

"nirbachon"             { return NIRBACHON; }
"dhoro"                 { return DHORO; }
"onnotha"               { return ONNOTHA; }

"dekhao"                { return DEKHAO; }
"dekhaoLine"            { return DEKHAOLINE; }
"nao"                   { return NAO; }
"size"                  { return SIZE; }

"sin"                   { return SIN; }
"cos"                   { return COS; }
"tan"                   { return TAN; }
"log10"                 { return LOG10; }
"log"                   { return LOG; }
"uporePurno"            { return UPOREPURNO; }
"nichePurno"            { return NICHEPURNO; }
"borgomul"              { return BORGOMUL; }
"porom"                 { return POROM; }

"purno"                 { return TYPE_PURNO; }
"doshomik"              { return TYPE_DOSHOMIK; }
"okkhor"                { return TYPE_OKKHOR; }
"shottiMiththa"         { return TYPE_BOOL; }
"khali"                 { return TYPE_KHALI; }
"okkhorMala"            { return TYPE_OKKHORMALA; }
"talika"                { return TYPE_TALIKA; }

"shotti"                { yylval.ival = 1; return TRUE_LITERAL; }
"miththa"               { yylval.ival = 0; return FALSE_LITERAL; }

[0-9]+\.[0-9]+          { yylval.dval = atof(yytext); return DECIMAL_LITERAL; }
[0-9]+                  { yylval.ival = atoi(yytext); return INT_LITERAL; }

\'[^\'\\]\'             { yylval.cval = yytext[1]; return CHAR_LITERAL; }
\'\\n\'                 { yylval.cval = '\n'; return CHAR_LITERAL; }
\'\\t\'                 { yylval.cval = '\t'; return CHAR_LITERAL; }
\'\\\\\'                { yylval.cval = '\\'; return CHAR_LITERAL; }
\'\\\'\'                { yylval.cval = '\''; return CHAR_LITERAL; }

\"([^"\n\\]|\\.)*\"     {
                            int len = strlen(yytext) - 2;
                            yylval.sval = process_string(yytext + 1, len);
                            return STRING_LITERAL;
                        }

"^^"                    { return POWER; }
"++"                    { return INCREMENT; }
"--"                    { return DECREMENT; }
"+="                    { return PLUS_ASSIGN; }
"-="                    { return MINUS_ASSIGN; }
"*="                    { return MULT_ASSIGN; }
"/="                    { return DIV_ASSIGN; }
"%="                    { return MOD_ASSIGN; }
"<="                    { return LE; }
">="                    { return GE; }
"=="                    { return EQ; }
"!="                    { return NE; }
"&&"                    { return AND; }
"||"                    { return OR; }
"<<"                    { return LEFT_SHIFT; }
">>"                    { return RIGHT_SHIFT; }
"->"                    { return ARROW; }

"+"                     { return PLUS; }
"-"                     { return MINUS; }
"*"                     { return MULTIPLY; }
"/"                     { return DIVIDE; }
"%"                     { return MODULO; }
"<"                     { return LT; }
">"                     { return GT; }
"="                     { return ASSIGN; }
"!"                     { return NOT; }
"&"                     { return BIT_AND; }
"|"                     { return BIT_OR; }
"^"                     { return BIT_XOR; }
"~"                     { return BIT_NOT; }

"("                     { return LPAREN; }
")"                     { return RPAREN; }
"{"                     { return LBRACE; }
"}"                     { return RBRACE; }
"["                     { return LBRACKET; }
"]"                     { return RBRACKET; }
";"                     { return SEMICOLON; }
","                     { return COMMA; }
":"                     { return COLON; }
"."                     { return DOT; }

[a-zA-Z_][a-zA-Z0-9_]* {
                            yylval.sval = strdup(yytext);
                            return IDENTIFIER;
                        }

.                       {
                            fprintf(stderr, "Lexical Error: Invalid token '%s' at line %d\n",
                                    yytext, line_num);
                            exit(1);
                        }

%%

int yywrap(void) { return 1; }
