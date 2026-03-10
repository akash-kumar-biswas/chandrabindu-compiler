#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>

/* Declared in parser.y */
extern FILE *output_file;
extern void run_program(void);
extern void generate_intermediate_code(FILE *out);
extern int yyparse(void);
extern FILE *yyin;

static int bs_fprintf(FILE *stream, const char *fmt, ...)
{
    va_list args;
    va_start(args, fmt);

    va_list args_copy;
    va_copy(args_copy, args);
    int written = vfprintf(stream, fmt, args);

    if (stream == stderr)
    {
        FILE *out = output_file;
        int need_close = 0;
        if (!out)
        {
            out = fopen("output.txt", "a");
            if (out)
                need_close = 1;
        }
        if (out)
        {
            vfprintf(out, fmt, args_copy);
            fflush(out);
            if (need_close)
                fclose(out);
        }
    }

    va_end(args_copy);
    va_end(args);
    return written;
}

#define fprintf bs_fprintf

int main(int argc, char **argv)
{
    if (argc < 2)
    {
        fprintf(stderr, "Usage: %s <input.cb>\n", argv[0]);
        return 1;
    }

    /* Open source file */
    yyin = fopen(argv[1], "r");
    if (!yyin)
    {
        fprintf(stderr, "Error: Cannot open input file '%s'\n", argv[1]);
        return 1;
    }

    /* Open output file */
    output_file = fopen("output.txt", "w");
    if (!output_file)
    {
        fprintf(stderr, "Error: Cannot open output.txt for writing\n");
        fclose(yyin);
        return 1;
    }

    /* Prepare IR file early so failed parses do not leave stale IR from old runs */
    {
        FILE *ir_file = fopen("intermediate.txt", "w");
        if (!ir_file)
        {
            fprintf(stderr, "Error: Cannot open intermediate.txt for writing\n");
            fclose(yyin);
            fclose(output_file);
            return 1;
        }
        fprintf(ir_file, "# Intermediate code not generated (parse/semantic error or early termination).\n");
        fclose(ir_file);
    }

    /* Parse (builds AST + populates function table) */
    yyparse();
    fclose(yyin);

    /* Optional phase: dump intermediate code */
    {
        FILE *ir_file = fopen("intermediate.txt", "w");
        if (!ir_file)
        {
            fprintf(stderr, "Error: Cannot open intermediate.txt for writing\n");
            fclose(output_file);
            return 1;
        }
        generate_intermediate_code(ir_file);
        fclose(ir_file);
    }

    /* Execute starting from mukkho */
    run_program();

    fclose(output_file);
    return 0;
}
