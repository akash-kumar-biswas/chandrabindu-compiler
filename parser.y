%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <limits.h>
#include <stdarg.h>

/* ---------------------------------------------------------- */
/*  External declarations from lexer                          */
/* ---------------------------------------------------------- */
extern int line_num;
extern int yylex(void);
void yyerror(const char *s);

/* Output file – set by main.c */
FILE *output_file = NULL;

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

static void mark_runtime_failure(void) {
    FILE *ir = fopen("intermediate.txt", "a");
    if (!ir) return;
    fprintf(ir, "\n# Execution failed at runtime.\n");
    fclose(ir);
}

/* ============================================================
   VALUE TYPES
   ============================================================ */
#ifndef BS_VTYPE_DEFINED
#define BS_VTYPE_DEFINED
typedef enum {
    T_INT = 0,
    T_DOUBLE,
    T_CHAR,
    T_BOOL,
    T_STRING,
    T_ARRAY,
    T_VOID,
    T_UNKNOWN
} VType;
#endif

static const char *vtype_name(VType t) {
    switch (t) {
        case T_INT:    return "purno";
        case T_DOUBLE: return "doshomik";
        case T_CHAR:   return "okkhor";
        case T_BOOL:   return "shottiMiththa";
        case T_STRING: return "okkhorMala";
        case T_ARRAY:  return "talika";
        case T_VOID:   return "khali";
        default:       return "unknown";
    }
}

/* ============================================================
   VALUE STRUCT
   ============================================================ */
typedef struct Value {
    VType  type;
    VType  elem_type;
    int    ival;
    double dval;
    char   cval;
    int    bval;
    char  *sval;
    struct Value *arr_data;
    int           arr_size;
} Value;

static Value make_int_val(int v)       { Value r; memset(&r,0,sizeof(r)); r.type=T_INT;    r.ival=v; return r; }
static Value make_double_val(double v) { Value r; memset(&r,0,sizeof(r)); r.type=T_DOUBLE; r.dval=v; return r; }
static Value make_char_val(char v)     { Value r; memset(&r,0,sizeof(r)); r.type=T_CHAR;   r.cval=v; return r; }
static Value make_bool_val(int v)      { Value r; memset(&r,0,sizeof(r)); r.type=T_BOOL;   r.bval=v; return r; }
static Value make_void_val(void)       { Value r; memset(&r,0,sizeof(r)); r.type=T_VOID;   return r; }
static Value make_string_val(const char *v) {
    Value r; memset(&r,0,sizeof(r));
    r.type = T_STRING;
    r.sval = strdup(v ? v : "");
    return r;
}
static Value make_array_val(Value *elems, int size, VType etype) {
    Value r; memset(&r,0,sizeof(r));
    r.type      = T_ARRAY;
    r.elem_type = etype;
    r.arr_size  = size;
    if (size > 0) {
        r.arr_data = malloc(sizeof(Value) * size);
        memcpy(r.arr_data, elems, sizeof(Value) * size);
    }
    return r;
}
static Value value_copy(Value v) {
    Value r = v;
    if (v.type == T_STRING && v.sval)
        r.sval = strdup(v.sval);
    if (v.type == T_ARRAY && v.arr_size > 0) {
        r.arr_data = malloc(sizeof(Value) * v.arr_size);
        for (int i = 0; i < v.arr_size; i++)
            r.arr_data[i] = value_copy(v.arr_data[i]);
    }
    return r;
}

static int is_numeric(VType t) { return t == T_INT || t == T_DOUBLE; }

static int is_truthy(Value v) {
    switch (v.type) {
        case T_INT:    return v.ival != 0;
        case T_DOUBLE: return v.dval != 0.0;
        case T_CHAR:   return v.cval != 0;
        case T_BOOL:   return v.bval != 0;
        default:       return 0;
    }
}

static void print_value(Value v, FILE *f) {
    switch (v.type) {
        case T_INT:    fprintf(f, "%d", v.ival); break;
        case T_DOUBLE:
            if (v.dval == (long long)v.dval)
                fprintf(f, "%.1f", v.dval);
            else
                fprintf(f, "%g", v.dval);
            break;
        case T_CHAR:   fprintf(f, "%c", v.cval); break;
        case T_BOOL:   fprintf(f, "%s", v.bval ? "shotti" : "miththa"); break;
        case T_STRING: fprintf(f, "%s", v.sval ? v.sval : ""); break;
        case T_ARRAY:
            for (int i = 0; i < v.arr_size; i++) {
                if (i > 0) fprintf(f, " ");
                print_value(v.arr_data[i], f);
            }
            break;
        case T_VOID: break;
        default: break;
    }
}

/* ============================================================
   AST NODE TYPES
   ============================================================ */
typedef enum {
    N_FUNC_DEF = 1,
    N_PARAM,
    N_BLOCK,
    N_VAR_DECL,
    N_ARRAY_DECL,
    N_IF,
    N_FOR,
    N_WHILE,
    N_SWITCH,
    N_CASE,
    N_RETURN,
    N_RETURN_VOID,
    N_BREAK,
    N_CONTINUE,
    N_DEKHAO,
    N_NAO,
    /* expressions */
    N_ASSIGN,
    N_COMPOUND_ASSIGN,
    N_BINARY,
    N_UNARY,
    N_POSTFIX_INC,
    N_POSTFIX_DEC,
    N_PREFIX_INC,
    N_PREFIX_DEC,
    N_INT_LIT,
    N_FLOAT_LIT,
    N_CHAR_LIT,
    N_STR_LIT,
    N_BOOL_LIT,
    N_IDENT,
    N_ARRAY_ACCESS,
    N_DOT_DAIRGHO,
    N_FUNC_CALL,
    N_ARRAY_LIT
} NodeType;

/* ============================================================
   AST NODE STRUCT
   ============================================================ */
typedef struct ASTNode {
    int             ntype;
    struct ASTNode *c0, *c1, *c2, *c3;
    struct ASTNode *next;
    int             ival;
    double          dval;
    char            cval;
    char           *sval;
    VType           vtype;
    VType           elem_vtype;
    int             op;
    int             line;
} ASTNode;

static ASTNode *new_node(int t) {
    ASTNode *n = calloc(1, sizeof(ASTNode));
    n->ntype = t;
    n->line  = line_num;
    return n;
}
static ASTNode *node_append(ASTNode *list, ASTNode *item) {
    if (!list) return item;
    ASTNode *cur = list;
    while (cur->next) cur = cur->next;
    cur->next = item;
    return list;
}

/* ============================================================
   SYMBOL TABLE
   ============================================================ */
typedef struct Symbol {
    char          *name;
    Value          val;
    struct Symbol *next;
} Symbol;

typedef struct Scope {
    Symbol       *syms;
    struct Scope *parent;
} Scope;

static Scope *current_scope = NULL;

static void scope_push(void) {
    Scope *s = calloc(1, sizeof(Scope));
    s->parent = current_scope;
    current_scope = s;
}
static void scope_pop(void) {
    if (!current_scope) return;
    Scope *p = current_scope->parent;
    Symbol *sym = current_scope->syms;
    while (sym) { Symbol *nx = sym->next; free(sym->name); free(sym); sym = nx; }
    free(current_scope);
    current_scope = p;
}
static Symbol *scope_lookup_local(const char *name) {
    Symbol *s = current_scope ? current_scope->syms : NULL;
    while (s) { if (strcmp(s->name, name)==0) return s; s = s->next; }
    return NULL;
}
static Symbol *scope_lookup(const char *name) {
    Scope *sc = current_scope;
    while (sc) {
        Symbol *s = sc->syms;
        while (s) { if (strcmp(s->name, name)==0) return s; s = s->next; }
        sc = sc->parent;
    }
    return NULL;
}
static void scope_declare(const char *name, Value val) {
    if (scope_lookup_local(name)) {
        fprintf(stderr, "Semantic Error: Redeclaration of '%s' in the same scope at line %d\n", name, line_num);
        exit(1);
    }
    Symbol *s = calloc(1, sizeof(Symbol));
    s->name = strdup(name);
    s->val  = value_copy(val);
    s->next = current_scope->syms;
    current_scope->syms = s;
}

/* ============================================================
   FUNCTION TABLE
   ============================================================ */
typedef struct Param { char *name; VType type; VType elem_type; struct Param *next; } Param;
typedef struct FuncDef {
    char           *name;
    Param          *params;
    int             param_count;
    VType           ret_type;
    VType           ret_elem_type;
    ASTNode        *body;
    struct FuncDef *next;
} FuncDef;

static FuncDef *func_table = NULL;

static void func_register(FuncDef *f) {
    FuncDef *cur = func_table;
    while (cur) {
        if (strcmp(cur->name, f->name)==0) {
            fprintf(stderr,"Semantic Error: Redefinition of function '%s' at line %d\n", f->name, line_num);
            exit(1);
        }
        cur = cur->next;
    }
    f->next = func_table; func_table = f;
}
static FuncDef *func_lookup(const char *name) {
    FuncDef *f = func_table;
    while (f) { if (strcmp(f->name, name)==0) return f; f = f->next; }
    return NULL;
}

/* ============================================================
   CONTROL FLOW
   ============================================================ */
typedef enum { CF_NORMAL=0, CF_BREAK, CF_CONTINUE, CF_RETURN } CFState;
static CFState cf_state  = CF_NORMAL;
static Value   return_val;
static VType   current_func_ret_type = T_VOID;
static int     loop_depth = 0;
static int     switch_depth = 0;

/* ============================================================
   FORWARD DECLARATIONS
   ============================================================ */
static Value exec_expr (ASTNode *n);
static void  exec_stmt (ASTNode *n);
static void  exec_block(ASTNode *n);
static Value exec_func_by_name(const char *name, ASTNode *arg_list, int ln);

static void collect_return_info(ASTNode *n, int *has_return_expr, int *has_return_void) {
    if (!n) return;
    if (n->ntype == N_RETURN) *has_return_expr = 1;
    if (n->ntype == N_RETURN_VOID) *has_return_void = 1;
    collect_return_info(n->c0, has_return_expr, has_return_void);
    collect_return_info(n->c1, has_return_expr, has_return_void);
    collect_return_info(n->c2, has_return_expr, has_return_void);
    collect_return_info(n->c3, has_return_expr, has_return_void);
    collect_return_info(n->next, has_return_expr, has_return_void);
}

static void validate_switch_case_defaults(ASTNode *case_list, int ln) {
    int default_count = 0;
    ASTNode *c = case_list;
    while (c) {
        if (c->ntype == N_CASE && c->ival == 1) default_count++;
        c = c->next;
    }
    if (default_count > 1) {
        fprintf(stderr, "Semantic Error: Multiple onnotha clauses in nirbachon at line %d\n", ln);
        exit(1);
    }
}

/* ============================================================
   TYPE HELPERS
   ============================================================ */
static int types_compatible(VType target, VType src) {
    if (target == src) return 1;
    if (target == T_DOUBLE && src == T_INT) return 1;
    return 0;
}
static Value coerce_value(Value v, VType target) {
    if (v.type == target) return v;
    if (target == T_DOUBLE && v.type == T_INT) return make_double_val((double)v.ival);
    if (target == T_INT && v.type == T_DOUBLE) {
        fprintf(stderr, "Warning: Implicit conversion from doshomik to purno at line %d\n", line_num);
        return make_int_val((int)v.dval);
    }
    return v;
}

static int parse_int_token(const char *tok, int *out) {
    char *end = NULL;
    long v = strtol(tok, &end, 10);
    if (!tok || tok[0] == '\0' || !end || *end != '\0') return 0;
    if (v < INT_MIN || v > INT_MAX) return 0;
    *out = (int)v;
    return 1;
}

static int parse_double_token(const char *tok, double *out) {
    char *end = NULL;
    double v = strtod(tok, &end);
    if (!tok || tok[0] == '\0' || !end || *end != '\0') return 0;
    *out = v;
    return 1;
}

static int parse_char_token(const char *tok, char *out) {
    if (!tok || !out) return 0;
    if (tok[0] == '\\' && tok[1] != '\0' && tok[2] == '\0') {
        switch (tok[1]) {
            case 'n': *out = '\n'; return 1;
            case 't': *out = '\t'; return 1;
            case 'r': *out = '\r'; return 1;
            case '\\': *out = '\\'; return 1;
            case '\'' : *out = '\''; return 1;
            default: return 0;
        }
    }
    if (tok[0] != '\0' && tok[1] == '\0') {
        *out = tok[0];
        return 1;
    }
    return 0;
}

static int parse_bool_token(const char *tok, int *out) {
    if (!tok || !out) return 0;
    if (strcmp(tok, "shotti") == 0 || strcmp(tok, "1") == 0) { *out = 1; return 1; }
    if (strcmp(tok, "miththa") == 0 || strcmp(tok, "0") == 0) { *out = 0; return 1; }
    return 0;
}

static char *read_nonempty_line(FILE *in) {
    char buf[4096];
    while (fgets(buf, sizeof(buf), in)) {
        int has_non_space = 0;
        for (int i = 0; buf[i] != '\0'; i++) {
            if (buf[i] != ' ' && buf[i] != '\t' && buf[i] != '\r' && buf[i] != '\n') {
                has_non_space = 1;
                break;
            }
        }
        if (has_non_space) return strdup(buf);
    }
    return NULL;
}

/* ============================================================
   ARITHMETIC
   ============================================================ */
static Value numeric_binary(Value a, Value b, int op) {
    int use_double = (a.type==T_DOUBLE || b.type==T_DOUBLE);
    double da = (a.type==T_DOUBLE)?a.dval:(double)a.ival;
    double db = (b.type==T_DOUBLE)?b.dval:(double)b.ival;
    int ia = a.ival, ib = b.ival;
    switch (op) {
        case '+': if(use_double) return make_double_val(da+db); return make_int_val(ia+ib);
        case '-': if(use_double) return make_double_val(da-db); return make_int_val(ia-ib);
        case '*': if(use_double) return make_double_val(da*db); return make_int_val(ia*ib);
        case '/':
            if (use_double) { if(db==0.0){fprintf(stderr,"Runtime Error: Division by zero\n"); mark_runtime_failure(); exit(1);} return make_double_val(da/db); }
            else            { if(ib==0){fprintf(stderr,"Runtime Error: Division by zero\n"); mark_runtime_failure(); exit(1);} return make_int_val(ia/ib); }
        case '%':
            if (ib==0){fprintf(stderr,"Runtime Error: Modulo by zero\n"); mark_runtime_failure(); exit(1);}
            return make_int_val(ia%ib);
        default: return make_int_val(0);
    }
}

/* ============================================================
   LVALUE ASSIGNMENT HELPER
   Assigns rhs to the lvalue represented by lhs_node.
   ============================================================ */
static void assign_lvalue(ASTNode *lhs, Value rhs, int ln) {
    if (!lhs) { fprintf(stderr,"Semantic Error: Invalid assignment target at line %d\n",ln); exit(1); }

    if (lhs->ntype == N_IDENT) {
        Symbol *s = scope_lookup(lhs->sval);
        if (!s) { fprintf(stderr,"Semantic Error: Undeclared identifier '%s' at line %d\n",lhs->sval,ln); exit(1); }
        /* Type coercion */
        if (s->val.type != rhs.type && is_numeric(s->val.type) && is_numeric(rhs.type))
            rhs = coerce_value(rhs, s->val.type);
        s->val = value_copy(rhs);
        return;
    }

    if (lhs->ntype == N_ARRAY_ACCESS) {
        /* lhs->c0 = base, lhs->c1 = index */
        ASTNode *base = lhs->c0;
        Value idx = exec_expr(lhs->c1);
        if (idx.type != T_INT) { fprintf(stderr,"Type Error: Index must be purno at line %d\n",ln); exit(1); }

        if (base->ntype == N_ARRAY_ACCESS) {
            /* Double-index: names[i][j] = 'x' */
            ASTNode *outer_base = base->c0;
            Value outer_idx = exec_expr(base->c1);
            if (outer_idx.type != T_INT) { fprintf(stderr,"Type Error: Outer index must be purno at line %d\n",ln); exit(1); }
            Symbol *s = scope_lookup(outer_base->sval);
            if (!s) { fprintf(stderr,"Semantic Error: Undeclared '%s' at line %d\n",outer_base->sval,ln); exit(1); }
            if (s->val.type != T_ARRAY || outer_idx.ival < 0 || outer_idx.ival >= s->val.arr_size) {
                fprintf(stderr,"Runtime Error: Array index out of bounds at line %d\n",ln); mark_runtime_failure(); exit(1);
            }
            Value *str_val = &s->val.arr_data[outer_idx.ival];
            if (str_val->type != T_STRING || !str_val->sval || idx.ival < 0 || idx.ival >= (int)strlen(str_val->sval)) {
                fprintf(stderr,"Runtime Error: String index out of bounds at line %d\n",ln); mark_runtime_failure(); exit(1);
            }
            if (rhs.type != T_CHAR) { fprintf(stderr,"Type Error: String assignment requires okkhor at line %d\n",ln); exit(1); }
            str_val->sval[idx.ival] = rhs.cval;
        } else {
            /* Single index */
            Symbol *s = scope_lookup(base->sval);
            if (!s) { fprintf(stderr,"Semantic Error: Undeclared '%s' at line %d\n",base->sval,ln); exit(1); }
            if (s->val.type == T_ARRAY) {
                if (idx.ival < 0 || idx.ival >= s->val.arr_size) {
                    fprintf(stderr,"Runtime Error: Array index out of bounds at line %d\n",ln); mark_runtime_failure(); exit(1);
                }
                s->val.arr_data[idx.ival] = value_copy(rhs);
            } else if (s->val.type == T_STRING) {
                if (!s->val.sval || idx.ival < 0 || idx.ival >= (int)strlen(s->val.sval)) {
                    fprintf(stderr,"Runtime Error: String index out of bounds at line %d\n",ln); mark_runtime_failure(); exit(1);
                }
                if (rhs.type != T_CHAR) { fprintf(stderr,"Type Error: String char assignment requires okkhor at line %d\n",ln); exit(1); }
                s->val.sval[idx.ival] = rhs.cval;
            } else {
                fprintf(stderr,"Type Error: Cannot index non-array/string at line %d\n",ln); exit(1);
            }
        }
        return;
    }

    fprintf(stderr,"Semantic Error: Invalid assignment target at line %d\n",ln); exit(1);
}

/* ============================================================
   EXPRESSION EVALUATOR
   ============================================================ */
static Value exec_expr(ASTNode *n) {
    if (!n) return make_void_val();

    switch (n->ntype) {

    case N_INT_LIT:   return make_int_val(n->ival);
    case N_FLOAT_LIT: return make_double_val(n->dval);
    case N_CHAR_LIT:  return make_char_val(n->cval);
    case N_STR_LIT:   return make_string_val(n->sval);
    case N_BOOL_LIT:  return make_bool_val(n->ival);

    case N_IDENT: {
        Symbol *s = scope_lookup(n->sval);
        if (!s) { fprintf(stderr,"Semantic Error: Undeclared identifier '%s' at line %d\n",n->sval,n->line); exit(1); }
        return value_copy(s->val);
    }

    case N_ARRAY_ACCESS: {
        Value base = exec_expr(n->c0);
        Value idx  = exec_expr(n->c1);
        if (idx.type != T_INT) { fprintf(stderr,"Type Error: Index must be purno at line %d\n",n->line); exit(1); }
        if (base.type == T_ARRAY) {
            if (idx.ival < 0 || idx.ival >= base.arr_size) {
                fprintf(stderr,"Runtime Error: Array index out of bounds (%d) at line %d\n",idx.ival,n->line); mark_runtime_failure(); exit(1);
            }
            return value_copy(base.arr_data[idx.ival]);
        } else if (base.type == T_STRING) {
            if (!base.sval || idx.ival < 0 || idx.ival >= (int)strlen(base.sval)) {
                fprintf(stderr,"Runtime Error: String index out of bounds (%d) at line %d\n",idx.ival,n->line); mark_runtime_failure(); exit(1);
            }
            return make_char_val(base.sval[idx.ival]);
        } else {
            fprintf(stderr,"Type Error: Cannot index non-array/string at line %d\n",n->line); exit(1);
        }
    }

    case N_DOT_DAIRGHO: {
        Value base = exec_expr(n->c0);
        if (base.type == T_ARRAY)  return make_int_val(base.arr_size);
        if (base.type == T_STRING) return make_int_val(base.sval ? (int)strlen(base.sval) : 0);
        fprintf(stderr,"Type Error: .dairgho() not applicable at line %d\n",n->line); exit(1);
    }

    case N_FUNC_CALL: {
        return exec_func_by_name(n->sval, n->c0, n->line);
    }

    case N_ARRAY_LIT: {
        int count = 0;
        ASTNode *e = n->c0;
        while (e) { count++; e = e->next; }
        Value *elems = count > 0 ? malloc(sizeof(Value)*count) : NULL;
        e = n->c0;
        VType etype = T_UNKNOWN;
        for (int i = 0; i < count; i++, e = e->next) {
            elems[i] = exec_expr(e);
            if (etype == T_UNKNOWN) etype = elems[i].type;
            else if (elems[i].type != etype) {
                if (!((etype==T_INT||etype==T_DOUBLE)&&(elems[i].type==T_INT||elems[i].type==T_DOUBLE))) {
                    fprintf(stderr,"Type Error: Array elements must be of the same type at line %d\n",n->line); exit(1);
                }
            }
        }
        Value arr = make_array_val(elems, count, etype==T_UNKNOWN?T_INT:etype);
        if (elems) free(elems);
        return arr;
    }

    case N_ASSIGN: {
        /* c0=lhs, c1=rhs, op='=' */
        Value rhs = exec_expr(n->c1);
        assign_lvalue(n->c0, rhs, n->line);
        return rhs;
    }

    case N_COMPOUND_ASSIGN: {
        /* c0=lhs (must be N_IDENT or N_ARRAY_ACCESS), c1=rhs, op=operator char */
        Value cur;
        if (n->c0->ntype == N_IDENT) {
            Symbol *s = scope_lookup(n->c0->sval);
            if (!s) { fprintf(stderr,"Semantic Error: Undeclared '%s' at line %d\n",n->c0->sval,n->line); exit(1); }
            cur = value_copy(s->val);
        } else {
            cur = exec_expr(n->c0);
        }
        Value rhs = exec_expr(n->c1);
        Value result = numeric_binary(cur, rhs, n->op);
        /* Coerce back to lhs type */
        if (n->c0->ntype == N_IDENT) {
            Symbol *s = scope_lookup(n->c0->sval);
            if (s->val.type == T_INT && result.type == T_DOUBLE)
                result = coerce_value(result, T_INT);
        }
        assign_lvalue(n->c0, result, n->line);
        return result;
    }

    case N_POSTFIX_INC: {
        if (n->c0->ntype != N_IDENT) { fprintf(stderr,"Semantic Error: ++ requires a variable at line %d\n",n->line); exit(1); }
        Symbol *s = scope_lookup(n->c0->sval);
        if (!s) { fprintf(stderr,"Semantic Error: Undeclared '%s' at line %d\n",n->c0->sval,n->line); exit(1); }
        Value old = value_copy(s->val);
        if (s->val.type==T_INT)    s->val.ival++;
        else if (s->val.type==T_DOUBLE) s->val.dval++;
        return old;
    }
    case N_POSTFIX_DEC: {
        if (n->c0->ntype != N_IDENT) { fprintf(stderr,"Semantic Error: -- requires a variable at line %d\n",n->line); exit(1); }
        Symbol *s = scope_lookup(n->c0->sval);
        if (!s) { fprintf(stderr,"Semantic Error: Undeclared '%s' at line %d\n",n->c0->sval,n->line); exit(1); }
        Value old = value_copy(s->val);
        if (s->val.type==T_INT)    s->val.ival--;
        else if (s->val.type==T_DOUBLE) s->val.dval--;
        return old;
    }
    case N_PREFIX_INC: {
        if (n->c0->ntype != N_IDENT) { fprintf(stderr,"Semantic Error: ++ requires a variable at line %d\n",n->line); exit(1); }
        Symbol *s = scope_lookup(n->c0->sval);
        if (!s) { fprintf(stderr,"Semantic Error: Undeclared '%s' at line %d\n",n->c0->sval,n->line); exit(1); }
        if (s->val.type==T_INT)    s->val.ival++;
        else if (s->val.type==T_DOUBLE) s->val.dval++;
        return value_copy(s->val);
    }
    case N_PREFIX_DEC: {
        if (n->c0->ntype != N_IDENT) { fprintf(stderr,"Semantic Error: -- requires a variable at line %d\n",n->line); exit(1); }
        Symbol *s = scope_lookup(n->c0->sval);
        if (!s) { fprintf(stderr,"Semantic Error: Undeclared '%s' at line %d\n",n->c0->sval,n->line); exit(1); }
        if (s->val.type==T_INT)    s->val.ival--;
        else if (s->val.type==T_DOUBLE) s->val.dval--;
        return value_copy(s->val);
    }

    case N_UNARY: {
        Value v = exec_expr(n->c0);
        switch (n->op) {
            case '-': if(v.type==T_INT) return make_int_val(-v.ival); if(v.type==T_DOUBLE) return make_double_val(-v.dval); break;
            case '+': return v;
            case '!': return make_bool_val(!is_truthy(v));
            case '~': if(v.type==T_INT) return make_int_val(~v.ival); break;
        }
        return v;
    }

    case N_BINARY: {
        int op = n->op;
        /* Short-circuit */
        if (op=='A') { Value a=exec_expr(n->c0); if(!is_truthy(a)) return make_bool_val(0); return make_bool_val(is_truthy(exec_expr(n->c1))); }
        if (op=='O') { Value a=exec_expr(n->c0); if(is_truthy(a))  return make_bool_val(1); return make_bool_val(is_truthy(exec_expr(n->c1))); }

        Value a = exec_expr(n->c0);
        Value b = exec_expr(n->c1);

        if (op=='P') {
            double da=(a.type==T_INT)?(double)a.ival:a.dval, db=(b.type==T_INT)?(double)b.ival:b.dval;
            return make_double_val(pow(da,db));
        }
        if (op=='+'||op=='-'||op=='*'||op=='/'||op=='%') {
            if (!is_numeric(a.type)||!is_numeric(b.type)) {
                fprintf(stderr,"Type Error: Arithmetic on non-numeric types at line %d\n",n->line); exit(1);
            }
            return numeric_binary(a,b,op);
        }
        if (op=='<'||op=='>'||op=='L'||op=='G'||op=='E'||op=='N') {
            int result=0;
            if (is_numeric(a.type)&&is_numeric(b.type)) {
                double da=(a.type==T_INT)?(double)a.ival:a.dval, db=(b.type==T_INT)?(double)b.ival:b.dval;
                switch(op){ case '<':result=da<db;break; case '>':result=da>db;break; case 'L':result=da<=db;break; case 'G':result=da>=db;break; case 'E':result=da==db;break; case 'N':result=da!=db;break; }
            } else if (a.type==T_CHAR&&b.type==T_CHAR) {
                switch(op){ case '<':result=a.cval<b.cval;break; case '>':result=a.cval>b.cval;break; case 'L':result=a.cval<=b.cval;break; case 'G':result=a.cval>=b.cval;break; case 'E':result=a.cval==b.cval;break; case 'N':result=a.cval!=b.cval;break; }
            } else if (a.type==T_BOOL&&b.type==T_BOOL) {
                switch(op){ case 'E':result=a.bval==b.bval;break; case 'N':result=a.bval!=b.bval;break; default: fprintf(stderr,"Type Error: Invalid boolean comparison at line %d\n",n->line); exit(1); }
            } else {
                fprintf(stderr,"Type Error: Incompatible types in comparison at line %d\n",n->line); exit(1);
            }
            return make_bool_val(result);
        }
        /* Bitwise */
        if (op=='&'||op=='|'||op=='^'||op=='R'||op=='S') {
            if (a.type!=T_INT||b.type!=T_INT) { fprintf(stderr,"Type Error: Bitwise operators require purno at line %d\n",n->line); exit(1); }
            switch(op){ case '&':return make_int_val(a.ival&b.ival); case '|':return make_int_val(a.ival|b.ival); case '^':return make_int_val(a.ival^b.ival); case 'S':return make_int_val(a.ival<<b.ival); case 'R':return make_int_val(a.ival>>b.ival); }
        }
        return make_void_val();
    }

    default:
        fprintf(stderr,"Internal Error: Unknown expression node %d at line %d\n",n->ntype,n->line); exit(1);
    }
}

/* ============================================================
   FUNCTION EXECUTOR
   ============================================================ */
static Value exec_func_by_name(const char *name, ASTNode *arg_list, int ln) {
    /* Count args */
    int argc = 0;
    ASTNode *a = arg_list;
    while (a) { argc++; a = a->next; }

    /* Math built-ins */
    int is_math_builtin = (strcmp(name,"sin")==0||strcmp(name,"cos")==0||strcmp(name,"tan")==0||
                           strcmp(name,"log")==0||strcmp(name,"log10")==0||strcmp(name,"uporePurno")==0||
                           strcmp(name,"nichePurno")==0||strcmp(name,"borgomul")==0||strcmp(name,"porom")==0);
    if (is_math_builtin) {
        if (argc != 1) { fprintf(stderr,"Semantic Error: Math function '%s' expects 1 argument at line %d\n",name,ln); exit(1); }
        Value av = exec_expr(arg_list);
        if (!is_numeric(av.type)) { fprintf(stderr,"Type Error: Math function '%s' expects numeric argument at line %d\n",name,ln); exit(1); }
        double d = (av.type==T_INT)?(double)av.ival:av.dval;
        if (strcmp(name,"sin")==0)        return make_double_val(sin(d));
        if (strcmp(name,"cos")==0)        return make_double_val(cos(d));
        if (strcmp(name,"tan")==0)        return make_double_val(tan(d));
        if (strcmp(name,"log")==0)        return make_double_val(log(d));
        if (strcmp(name,"log10")==0)      return make_double_val(log10(d));
        if (strcmp(name,"uporePurno")==0) return make_double_val(ceil(d));
        if (strcmp(name,"nichePurno")==0) return make_double_val(floor(d));
        if (strcmp(name,"borgomul")==0)   return make_double_val(sqrt(d));
        if (strcmp(name,"porom")==0)      return make_int_val((int)fabs(d));
    }

    /* User-defined */
    FuncDef *f = func_lookup(name);
    if (!f) { fprintf(stderr,"Semantic Error: Undeclared function '%s' at line %d\n",name,ln); exit(1); }
    if (argc != f->param_count) {
        fprintf(stderr,"Semantic Error: Argument count mismatch in call to '%s': expected %d, got %d at line %d\n",
                name, f->param_count, argc, ln); exit(1);
    }

    Value args[64];
    a = arg_list;
    for (int i = 0; i < argc; i++, a = a->next) args[i] = exec_expr(a);

    Scope *saved_scope = current_scope;
    current_scope = NULL;
    scope_push();

    Param *p = f->params;
    for (int i = 0; i < argc; i++, p = p->next) {
        Value cv = coerce_value(args[i], p->type);
        scope_declare(p->name, cv);
    }

    CFState saved_cf = cf_state;
    Value   saved_rv = return_val;
    VType   saved_rt = current_func_ret_type;
    cf_state             = CF_NORMAL;
    current_func_ret_type = f->ret_type;

    exec_block(f->body);

    Value result = (cf_state == CF_RETURN) ? value_copy(return_val) : make_void_val();

    cf_state             = saved_cf;
    return_val           = saved_rv;
    current_func_ret_type = saved_rt;

    scope_pop();
    current_scope = saved_scope;

    if (f->ret_type != T_VOID && result.type != f->ret_type && types_compatible(f->ret_type, result.type))
        result = coerce_value(result, f->ret_type);

    return result;
}

/* ============================================================
   STATEMENT EXECUTOR
   ============================================================ */
static void exec_stmt(ASTNode *n) {
    if (!n || cf_state != CF_NORMAL) return;

    switch (n->ntype) {

    case N_VAR_DECL: {
        int name_count = 0; ASTNode *id = n->c0; while(id){name_count++;id=id->next;}
        int val_count  = 0; ASTNode *ve = n->c1; while(ve){val_count++;ve=ve->next;}
        if (n->c1 && name_count != val_count) {
            fprintf(stderr,"Semantic Error: Variable count (%d) != value count (%d) at line %d\n",name_count,val_count,n->line); exit(1);
        }
        id = n->c0; ve = n->c1;
        while (id) {
            Value v;
            if (ve) {
                Value init = exec_expr(ve);
                if (!types_compatible(n->vtype, init.type)) {
                    fprintf(stderr,"Type Error: Cannot assign %s to %s for '%s' at line %d\n",
                            vtype_name(init.type),vtype_name(n->vtype),id->sval,n->line); exit(1);
                }
                v = coerce_value(init, n->vtype);
                ve = ve->next;
            } else {
                switch(n->vtype){
                    case T_INT:    v=make_int_val(0);      break;
                    case T_DOUBLE: v=make_double_val(0.0); break;
                    case T_CHAR:   v=make_char_val('\0');  break;
                    case T_BOOL:   v=make_bool_val(0);     break;
                    case T_STRING: v=make_string_val("");  break;
                    default:       v=make_void_val();      break;
                }
            }
            scope_declare(id->sval, v);
            id = id->next;
        }
        break;
    }

    case N_ARRAY_DECL: {
        Value arr;
        if (n->c0) {
            int count=0; ASTNode *e=n->c0; while(e){count++;e=e->next;}
            Value *elems = count>0?malloc(sizeof(Value)*count):NULL;
            e=n->c0;
            for (int i=0;i<count;i++,e=e->next) {
                elems[i]=exec_expr(e);
                if (!types_compatible(n->elem_vtype, elems[i].type)) {
                    fprintf(stderr,"Type Error: Array element type mismatch at line %d\n",n->line); exit(1);
                }
                elems[i]=coerce_value(elems[i],n->elem_vtype);
            }
            arr=make_array_val(elems,count,n->elem_vtype);
            if(elems) free(elems);
        } else {
            arr=make_array_val(NULL,0,n->elem_vtype);
        }
        scope_declare(n->sval, arr);
        break;
    }

    case N_IF: {
        Value cond = exec_expr(n->c0);
        if (is_truthy(cond)) {
            scope_push(); exec_block(n->c1); scope_pop();
        } else if (n->c2) {
            if (n->c2->ntype == N_IF) exec_stmt(n->c2);
            else { scope_push(); exec_block(n->c2); scope_pop(); }
        }
        break;
    }

    case N_FOR: {
        scope_push();
        loop_depth++;
        if (n->c0) {
            if (n->c0->ntype == N_VAR_DECL || n->c0->ntype == N_ARRAY_DECL)
                exec_stmt(n->c0);
            else
                exec_expr(n->c0);
        }
        while (cf_state == CF_NORMAL) {
            if (n->c1) { Value cond=exec_expr(n->c1); if(!is_truthy(cond)) break; }
            scope_push(); exec_block(n->c3); scope_pop();
            if (cf_state==CF_BREAK)    { cf_state=CF_NORMAL; break; }
            if (cf_state==CF_CONTINUE) { cf_state=CF_NORMAL; }
            if (cf_state==CF_RETURN)   break;
            if (n->c2) exec_expr(n->c2);  /* for_update is also an expr */
        }
        loop_depth--;
        scope_pop();
        break;
    }

    case N_WHILE: {
        loop_depth++;
        while (cf_state == CF_NORMAL) {
            Value cond=exec_expr(n->c0); if(!is_truthy(cond)) break;
            scope_push(); exec_block(n->c1); scope_pop();
            if (cf_state==CF_BREAK)    { cf_state=CF_NORMAL; break; }
            if (cf_state==CF_CONTINUE) { cf_state=CF_NORMAL; }
            if (cf_state==CF_RETURN)   break;
        }
        loop_depth--;
        break;
    }

    case N_SWITCH: {
        scope_push();
        switch_depth++;
        Value sw_val = exec_expr(n->c0);
        ASTNode *case_node = n->c1;
        int matched=0;
        ASTNode *default_node=NULL;
        while (case_node) {
            if (case_node->ival==1) { default_node=case_node; case_node=case_node->next; continue; }
            Value cv=exec_expr(case_node->c0);
            int cmp=0;
            if (sw_val.type==T_INT&&cv.type==T_INT) cmp=(sw_val.ival==cv.ival);
            else if (sw_val.type==T_CHAR&&cv.type==T_CHAR) cmp=(sw_val.cval==cv.cval);
            else if (sw_val.type==T_STRING&&cv.type==T_STRING) cmp=(strcmp(sw_val.sval?sw_val.sval:"", cv.sval?cv.sval:"")==0);
            else if (sw_val.type==T_BOOL&&cv.type==T_BOOL) cmp=(sw_val.bval==cv.bval);
            else if (is_numeric(sw_val.type)&&is_numeric(cv.type)) {
                double a=(sw_val.type==T_INT)?(double)sw_val.ival:sw_val.dval;
                double b=(cv.type==T_INT)?(double)cv.ival:cv.dval;
                cmp=(a==b);
            } else {
                fprintf(stderr,"Type Error: Incompatible dhoro value type in nirbachon at line %d\n",case_node->line);
                exit(1);
            }
            if (cmp) matched=1;
            if (matched) {
                ASTNode *s=case_node->c1;
                while(s&&cf_state==CF_NORMAL){exec_stmt(s);s=s->next;}
                if (cf_state==CF_BREAK){cf_state=CF_NORMAL;goto sw_done;}
                if (cf_state!=CF_NORMAL) goto sw_done;
            }
            case_node=case_node->next;
        }
        if (!matched&&default_node) {
            ASTNode *s=default_node->c1;
            while(s&&cf_state==CF_NORMAL){exec_stmt(s);s=s->next;}
            if (cf_state==CF_BREAK) cf_state=CF_NORMAL;
        }
        sw_done:;
        switch_depth--;
        scope_pop();
        break;
    }

    case N_RETURN: {
        return_val = n->c0 ? exec_expr(n->c0) : make_void_val();
        if (current_func_ret_type != T_VOID && n->c0 && types_compatible(current_func_ret_type, return_val.type))
            return_val = coerce_value(return_val, current_func_ret_type);
        cf_state = CF_RETURN;
        break;
    }
    case N_RETURN_VOID: {
        if (current_func_ret_type != T_VOID) {
            fprintf(stderr,"Type Error: Non-khali function must return a value at line %d\n",n->line); exit(1);
        }
        return_val = make_void_val(); cf_state = CF_RETURN; break;
    }
    case N_CONTINUE: {
        if (loop_depth <= 0) {
            fprintf(stderr,"Semantic Error: 'cholteThako' used outside loop at line %d\n",n->line);
            exit(1);
        }
        cf_state = CF_CONTINUE;
        break;
    }
    case N_BREAK: {
        if (loop_depth <= 0 && switch_depth <= 0) {
            fprintf(stderr,"Semantic Error: 'thamo' used outside loop/switch at line %d\n",n->line);
            exit(1);
        }
        cf_state = CF_BREAK;
        break;
    }

    case N_DEKHAO: {
        ASTNode *a = n->c0;
        while (a) {
            Value v = exec_expr(a);
            if (output_file) print_value(v, output_file);
            print_value(v, stdout);
            a = a->next;
        }
        if (n->ival) {
            if (output_file) fputc('\n', output_file);
            fputc('\n', stdout);
        }
        if (output_file) fflush(output_file);
        fflush(stdout);
        break;
    }

    case N_NAO: {
        const char *tname = n->c0->sval;
        Symbol *s = scope_lookup(tname);
        if (!s) { fprintf(stderr,"Semantic Error: Undeclared '%s' at line %d\n",tname,n->line); exit(1); }

        if (s->val.type == T_ARRAY) {
            char *line = read_nonempty_line(stdin);
            if (!line) { fprintf(stderr,"Runtime Error: Invalid input\n"); mark_runtime_failure(); exit(1); }

            Value *elems = NULL;
            int count = 0;
            char *tok = strtok(line, " \t\r\n");

            while (tok) {
                Value v;
                int iv;
                double dv;
                char cv;
                int bv;

                switch (s->val.elem_type) {
                    case T_INT:
                        if (!parse_int_token(tok, &iv)) {
                            fprintf(stderr,"Runtime Error: Invalid purno value '%s' in nao(%s) at line %d\n", tok, tname, n->line);
                            mark_runtime_failure();
                            exit(1);
                        }
                        v = make_int_val(iv);
                        break;
                    case T_DOUBLE:
                        if (!parse_double_token(tok, &dv)) {
                            fprintf(stderr,"Runtime Error: Invalid doshomik value '%s' in nao(%s) at line %d\n", tok, tname, n->line);
                            mark_runtime_failure();
                            exit(1);
                        }
                        v = make_double_val(dv);
                        break;
                    case T_CHAR:
                        if (!parse_char_token(tok, &cv)) {
                            fprintf(stderr,"Runtime Error: Invalid okkhor value '%s' in nao(%s) at line %d\n", tok, tname, n->line);
                            mark_runtime_failure();
                            exit(1);
                        }
                        v = make_char_val(cv);
                        break;
                    case T_BOOL:
                        if (!parse_bool_token(tok, &bv)) {
                            fprintf(stderr,"Runtime Error: Invalid shottiMiththa value '%s' in nao(%s) at line %d\n", tok, tname, n->line);
                            mark_runtime_failure();
                            exit(1);
                        }
                        v = make_bool_val(bv);
                        break;
                    case T_STRING:
                        v = make_string_val(tok);
                        break;
                    default:
                        fprintf(stderr,"Runtime Error: Unsupported array element type in nao(%s) at line %d\n", tname, n->line);
                        mark_runtime_failure();
                        exit(1);
                }

                elems = realloc(elems, sizeof(Value) * (count + 1));
                elems[count++] = v;
                tok = strtok(NULL, " \t\r\n");
            }

            s->val = make_array_val(elems, count, s->val.elem_type);
            if (elems) free(elems);
            free(line);
            break;
        }

        switch (s->val.type) {
            case T_INT:    { int tmp; if(scanf("%d",&tmp)!=1){fprintf(stderr,"Runtime Error: Invalid input\n"); mark_runtime_failure(); exit(1);} s->val.ival=tmp; break; }
            case T_DOUBLE: { double tmp; if(scanf("%lf",&tmp)!=1){fprintf(stderr,"Runtime Error: Invalid input\n"); mark_runtime_failure(); exit(1);} s->val.dval=tmp; break; }
            case T_CHAR:   { char tmp; if(scanf(" %c",&tmp)!=1){fprintf(stderr,"Runtime Error: Invalid input\n"); mark_runtime_failure(); exit(1);} s->val.cval=tmp; break; }
            case T_STRING: { char buf[1024]; if(scanf("%1023s",buf)!=1){fprintf(stderr,"Runtime Error: Invalid input\n"); mark_runtime_failure(); exit(1);} if(s->val.sval)free(s->val.sval); s->val.sval=strdup(buf); break; }
            default: fprintf(stderr,"Runtime Error: Unsupported type in nao() at line %d\n",n->line); mark_runtime_failure(); exit(1);
        }
        break;
    }

    default:
        /* Expression statement */
        exec_expr(n);
        break;
    }
}

static void exec_block(ASTNode *block) {
    if (!block) return;
    ASTNode *s = block->c0;
    while (s && cf_state == CF_NORMAL) { exec_stmt(s); s = s->next; }
}

/* ============================================================
   INTERMEDIATE CODE GENERATION (optional requirement)
   ============================================================ */
static int ir_temp_counter = 0;
static int ir_label_counter = 0;

static char *ir_strdup(const char *s) {
    return strdup(s ? s : "");
}

static char *ir_new_temp(void) {
    char buf[32];
    snprintf(buf, sizeof(buf), "t%d", ir_temp_counter++);
    return ir_strdup(buf);
}

static char *ir_new_label(void) {
    char buf[32];
    snprintf(buf, sizeof(buf), "L%d", ir_label_counter++);
    return ir_strdup(buf);
}

static const char *ir_op_name(int op) {
    switch (op) {
        case 'L': return "<=";
        case 'G': return ">=";
        case 'E': return "==";
        case 'N': return "!=";
        case 'A': return "&&";
        case 'O': return "||";
        case 'P': return "^^";
        case 'S': return "<<";
        case 'R': return ">>";
        default: {
            static char cbuf[2];
            cbuf[0] = (char)op;
            cbuf[1] = '\0';
            return cbuf;
        }
    }
}

static char *ir_emit_expr(ASTNode *n, FILE *out);
static void ir_emit_stmt(ASTNode *n, FILE *out);
static void ir_emit_stmt_list(ASTNode *n, FILE *out);

static char *ir_emit_expr(ASTNode *n, FILE *out) {
    if (!n) return ir_strdup("void");

    switch (n->ntype) {
        case N_INT_LIT: {
            char buf[64];
            snprintf(buf, sizeof(buf), "%d", n->ival);
            return ir_strdup(buf);
        }
        case N_FLOAT_LIT: {
            char buf[64];
            snprintf(buf, sizeof(buf), "%g", n->dval);
            return ir_strdup(buf);
        }
        case N_CHAR_LIT: {
            char buf[16];
            snprintf(buf, sizeof(buf), "'%c'", n->cval);
            return ir_strdup(buf);
        }
        case N_STR_LIT: {
            char *res = malloc(strlen(n->sval ? n->sval : "") + 3);
            sprintf(res, "\"%s\"", n->sval ? n->sval : "");
            return res;
        }
        case N_BOOL_LIT:
            return ir_strdup(n->ival ? "shotti" : "miththa");
        case N_IDENT:
            return ir_strdup(n->sval);
        case N_ARRAY_ACCESS: {
            char *base = ir_emit_expr(n->c0, out);
            char *idx = ir_emit_expr(n->c1, out);
            char *tmp = ir_new_temp();
            fprintf(out, "%s = %s[%s]\n", tmp, base, idx);
            return tmp;
        }
        case N_DOT_DAIRGHO: {
            char *base = ir_emit_expr(n->c0, out);
            char *tmp = ir_new_temp();
            fprintf(out, "%s = dairgho(%s)\n", tmp, base);
            return tmp;
        }
        case N_FUNC_CALL: {
            int argc = 0;
            ASTNode *a = n->c0;
            while (a) {
                char *arg = ir_emit_expr(a, out);
                fprintf(out, "param %s\n", arg);
                argc++;
                a = a->next;
            }
            char *tmp = ir_new_temp();
            fprintf(out, "%s = call %s, %d\n", tmp, n->sval, argc);
            return tmp;
        }
        case N_ASSIGN: {
            char *rhs = ir_emit_expr(n->c1, out);
            if (n->c0 && n->c0->ntype == N_IDENT) {
                fprintf(out, "%s = %s\n", n->c0->sval, rhs);
                return ir_strdup(n->c0->sval);
            }
            if (n->c0 && n->c0->ntype == N_ARRAY_ACCESS) {
                char *base = ir_emit_expr(n->c0->c0, out);
                char *idx = ir_emit_expr(n->c0->c1, out);
                fprintf(out, "%s[%s] = %s\n", base, idx, rhs);
                return rhs;
            }
            fprintf(out, "<assign_target> = %s\n", rhs);
            return rhs;
        }
        case N_COMPOUND_ASSIGN:
        case N_BINARY: {
            char *l = ir_emit_expr(n->c0, out);
            char *r = ir_emit_expr(n->c1, out);
            char *tmp = ir_new_temp();
            fprintf(out, "%s = %s %s %s\n", tmp, l, ir_op_name(n->op), r);
            if (n->ntype == N_COMPOUND_ASSIGN && n->c0 && n->c0->ntype == N_IDENT) {
                fprintf(out, "%s = %s\n", n->c0->sval, tmp);
                return ir_strdup(n->c0->sval);
            }
            return tmp;
        }
        case N_UNARY: {
            char *v = ir_emit_expr(n->c0, out);
            char *tmp = ir_new_temp();
            fprintf(out, "%s = %s%s\n", tmp, ir_op_name(n->op), v);
            return tmp;
        }
        case N_POSTFIX_INC:
        case N_PREFIX_INC:
        case N_POSTFIX_DEC:
        case N_PREFIX_DEC: {
            char *v = ir_emit_expr(n->c0, out);
            const char *op = (n->ntype == N_POSTFIX_INC || n->ntype == N_PREFIX_INC) ? "+" : "-";
            fprintf(out, "%s = %s %s 1\n", v, v, op);
            return v;
        }
        case N_ARRAY_LIT: {
            char *tmp = ir_new_temp();
            fprintf(out, "%s = []\n", tmp);
            ASTNode *e = n->c0;
            while (e) {
                char *v = ir_emit_expr(e, out);
                fprintf(out, "push %s, %s\n", tmp, v);
                e = e->next;
            }
            return tmp;
        }
        default:
            return ir_strdup("<expr>");
    }
}

static void ir_emit_stmt_list(ASTNode *n, FILE *out) {
    while (n) {
        ir_emit_stmt(n, out);
        n = n->next;
    }
}

static void ir_emit_stmt(ASTNode *n, FILE *out) {
    if (!n) return;

    switch (n->ntype) {
        case N_VAR_DECL: {
            ASTNode *id = n->c0;
            ASTNode *val = n->c1;
            while (id) {
                fprintf(out, "decl %s : %s\n", id->sval, vtype_name(n->vtype));
                if (val) {
                    char *rhs = ir_emit_expr(val, out);
                    fprintf(out, "%s = %s\n", id->sval, rhs);
                    val = val->next;
                }
                id = id->next;
            }
            break;
        }
        case N_ARRAY_DECL: {
            fprintf(out, "decl %s : talika<%s>\n", n->sval, vtype_name(n->elem_vtype));
            if (n->c0) {
                ASTNode *e = n->c0;
                while (e) {
                    char *v = ir_emit_expr(e, out);
                    fprintf(out, "push %s, %s\n", n->sval, v);
                    e = e->next;
                }
            }
            break;
        }
        case N_IF: {
            char *cond = ir_emit_expr(n->c0, out);
            char *l_else = ir_new_label();
            char *l_end = ir_new_label();
            fprintf(out, "ifFalse %s goto %s\n", cond, l_else);
            ir_emit_stmt_list(n->c1 ? n->c1->c0 : NULL, out);
            fprintf(out, "goto %s\n", l_end);
            fprintf(out, "%s:\n", l_else);
            if (n->c2) {
                if (n->c2->ntype == N_IF) ir_emit_stmt(n->c2, out);
                else ir_emit_stmt_list(n->c2->c0, out);
            }
            fprintf(out, "%s:\n", l_end);
            break;
        }
        case N_FOR: {
            char *l_cond = ir_new_label();
            char *l_body = ir_new_label();
            char *l_upd = ir_new_label();
            char *l_end = ir_new_label();
            if (n->c0) ir_emit_stmt(n->c0, out);
            fprintf(out, "%s:\n", l_cond);
            if (n->c1) {
                char *cond = ir_emit_expr(n->c1, out);
                fprintf(out, "ifFalse %s goto %s\n", cond, l_end);
            }
            fprintf(out, "%s:\n", l_body);
            ir_emit_stmt_list(n->c3 ? n->c3->c0 : NULL, out);
            fprintf(out, "%s:\n", l_upd);
            if (n->c2) ir_emit_expr(n->c2, out);
            fprintf(out, "goto %s\n", l_cond);
            fprintf(out, "%s:\n", l_end);
            break;
        }
        case N_WHILE: {
            char *l_cond = ir_new_label();
            char *l_end = ir_new_label();
            fprintf(out, "%s:\n", l_cond);
            {
                char *cond = ir_emit_expr(n->c0, out);
                fprintf(out, "ifFalse %s goto %s\n", cond, l_end);
            }
            ir_emit_stmt_list(n->c1 ? n->c1->c0 : NULL, out);
            fprintf(out, "goto %s\n", l_cond);
            fprintf(out, "%s:\n", l_end);
            break;
        }
        case N_SWITCH: {
            char *sw = ir_emit_expr(n->c0, out);
            ASTNode *c = n->c1;
            char *l_end = ir_new_label();
            while (c) {
                if (c->ival == 0) {
                    char *lv = ir_emit_expr(c->c0, out);
                    char *l_case = ir_new_label();
                    fprintf(out, "if %s == %s goto %s\n", sw, lv, l_case);
                    fprintf(out, "%s:\n", l_case);
                    ir_emit_stmt_list(c->c1, out);
                } else {
                    fprintf(out, "default:\n");
                    ir_emit_stmt_list(c->c1, out);
                }
                c = c->next;
            }
            fprintf(out, "%s:\n", l_end);
            break;
        }
        case N_RETURN: {
            char *v = ir_emit_expr(n->c0, out);
            fprintf(out, "return %s\n", v);
            break;
        }
        case N_RETURN_VOID:
            fprintf(out, "return\n");
            break;
        case N_BREAK:
            fprintf(out, "break\n");
            break;
        case N_CONTINUE:
            fprintf(out, "continue\n");
            break;
        case N_DEKHAO: {
            ASTNode *a = n->c0;
            while (a) {
                char *v = ir_emit_expr(a, out);
                fprintf(out, "print %s\n", v);
                a = a->next;
            }
            if (n->ival) fprintf(out, "print_newline\n");
            break;
        }
        case N_NAO:
            fprintf(out, "input %s\n", n->c0 ? n->c0->sval : "<target>");
            break;
        default:
            (void)ir_emit_expr(n, out);
            break;
    }
}

static void ir_emit_function(FuncDef *f, FILE *out) {
    fprintf(out, "func %s:\n", f->name);
    {
        Param *p = f->params;
        while (p) {
            fprintf(out, "param_decl %s : %s\n", p->name, vtype_name(p->type));
            p = p->next;
        }
    }
    ir_emit_stmt_list(f->body ? f->body->c0 : NULL, out);
    fprintf(out, "endfunc %s\n\n", f->name);
}

static void ir_emit_all_functions(FuncDef *f, FILE *out) {
    if (!f) return;
    ir_emit_all_functions(f->next, out);
    ir_emit_function(f, out);
}

void generate_intermediate_code(FILE *out) {
    if (!out) return;
    ir_temp_counter = 0;
    ir_label_counter = 0;
    fprintf(out, "# BanglaScript Intermediate Code (TAC-like)\n\n");
    ir_emit_all_functions(func_table, out);
    fflush(out);
}

void run_program(void) {
    FuncDef *mukkho = func_lookup("mukkho");
    if (!mukkho) { fprintf(stderr,"Semantic Error: No 'mukkho' function defined\n"); exit(1); }
    current_scope = NULL;
    scope_push();
    cf_state = CF_NORMAL;
    exec_func_by_name("mukkho", NULL, 0);
    scope_pop();
}

%}

/* Types that must appear in parser.tab.h for lex.yy.c to compile */
%code requires {
#ifndef BS_VTYPE_DEFINED
#define BS_VTYPE_DEFINED
typedef enum { T_INT=0, T_DOUBLE, T_CHAR, T_BOOL, T_STRING, T_ARRAY, T_VOID, T_UNKNOWN } VType;
#endif
#ifndef BS_ASTNODE_FWD
#define BS_ASTNODE_FWD
typedef struct ASTNode ASTNode;
#endif
}

/* ============================================================
   BISON UNION
   ============================================================ */
%union {
    int      ival;
    double   dval;
    char     cval;
    char    *sval;
    VType    vtype;
    ASTNode *node;
}

/* ============================================================
   TOKENS
   ============================================================ */
%token KAJ MUKKHO FERAO
%token JODI NAHOLEJODI NAHOLE
%token GHURAO JOTOKKHON CHOLTETHAKO THAMO
%token NIRBACHON DHORO ONNOTHA
%token DEKHAO DEKHAOLINE NAO DAIRGHO
%token SIN COS TAN LOG LOG10 UPOREPURNO NICHEPURNO BORGOMUL POROM
%token TYPE_PURNO TYPE_DOSHOMIK TYPE_OKKHOR TYPE_BOOL TYPE_KHALI
%token TYPE_OKKHORMALA TYPE_TALIKA
%token ARROW SEMICOLON COMMA COLON DOT
%token LPAREN RPAREN LBRACE RBRACE LBRACKET RBRACKET
%token ASSIGN PLUS_ASSIGN MINUS_ASSIGN MULT_ASSIGN DIV_ASSIGN MOD_ASSIGN
%token INCREMENT DECREMENT
%token PLUS MINUS MULTIPLY DIVIDE MODULO POWER
%token LT GT LE GE EQ NE
%token AND OR NOT
%token BIT_AND BIT_OR BIT_XOR BIT_NOT LEFT_SHIFT RIGHT_SHIFT

%token <ival> INT_LITERAL TRUE_LITERAL FALSE_LITERAL
%token <dval> DECIMAL_LITERAL
%token <cval> CHAR_LITERAL
%token <sval> STRING_LITERAL IDENTIFIER

/* ============================================================
   NON-TERMINAL TYPES
   ============================================================ */
%type <node> program func_def_list func_def
%type <node> param_list_opt param_list param
%type <vtype> type elem_type
%type <node> block stmt_list stmt
%type <node> var_decl id_list expr_list
%type <node> if_stmt else_part
%type <node> for_stmt for_init for_update for_decl_init
%type <node> while_stmt
%type <node> switch_stmt case_list case_clause
%type <node> return_stmt
%type <node> io_stmt
%type <node> expr arg_list_opt arg_list
%type <node> elem_list_opt elem_list

/* ============================================================
   OPERATOR PRECEDENCE (lowest → highest)
   ============================================================ */
%right ASSIGN PLUS_ASSIGN MINUS_ASSIGN MULT_ASSIGN DIV_ASSIGN MOD_ASSIGN
%left  OR
%left  AND
%left  BIT_OR
%left  BIT_XOR
%left  BIT_AND
%left  EQ NE
%left  LT GT LE GE
%left  LEFT_SHIFT RIGHT_SHIFT
%left  PLUS MINUS
%left  MULTIPLY DIVIDE MODULO
%right POWER
%right UMINUS UPLUS UNOT UBITNOT
%left  INCREMENT DECREMENT
%left  DOT LBRACKET LPAREN

%%

/* ============================================================
   GRAMMAR RULES
   ============================================================ */

program
    : func_def_list { $$ = $1; }
    ;

func_def_list
    : func_def                { $$ = $1; }
    | func_def_list func_def  { $$ = $1; }
    ;

func_def
    : KAJ IDENTIFIER LPAREN param_list_opt RPAREN ARROW type block
        {
            FuncDef *f = calloc(1, sizeof(FuncDef));
            f->name = $2; f->ret_type = $7;
            Param *phead=NULL, *ptail=NULL; int pc=0;
            ASTNode *pn = $4;
            while (pn) {
                Param *p=calloc(1,sizeof(Param));
                p->name=strdup(pn->sval); p->type=pn->vtype; p->elem_type=pn->elem_vtype;
                if(!phead) phead=p; else ptail->next=p;
                ptail=p; pc++; pn=pn->next;
            }
            f->params=phead; f->param_count=pc; f->body=$8;

            {
                int has_return_expr = 0, has_return_void = 0;
                collect_return_info(f->body, &has_return_expr, &has_return_void);
                if (f->ret_type == T_VOID && has_return_expr) {
                    fprintf(stderr,"Type Error: khali function cannot return a value at line %d\n", line_num);
                    exit(1);
                }
                if (f->ret_type != T_VOID && has_return_void) {
                    fprintf(stderr,"Type Error: Non-khali function must return a value at line %d\n", line_num);
                    exit(1);
                }
                if (f->ret_type != T_VOID && !has_return_expr) {
                    fprintf(stderr,"Semantic Error: Missing return in non-khali function '%s' at line %d\n", f->name, line_num);
                    exit(1);
                }
            }

            func_register(f); $$=NULL;
        }
    | KAJ MUKKHO LPAREN RPAREN ARROW type block
        {
            FuncDef *f=calloc(1,sizeof(FuncDef));
            f->name=strdup("mukkho"); f->ret_type=$6;
            f->params=NULL; f->param_count=0; f->body=$7;

            {
                int has_return_expr = 0, has_return_void = 0;
                collect_return_info(f->body, &has_return_expr, &has_return_void);
                if (f->ret_type == T_VOID && has_return_expr) {
                    fprintf(stderr,"Type Error: khali function cannot return a value at line %d\n", line_num);
                    exit(1);
                }
                if (f->ret_type != T_VOID && has_return_void) {
                    fprintf(stderr,"Type Error: Non-khali function must return a value at line %d\n", line_num);
                    exit(1);
                }
                if (f->ret_type != T_VOID && !has_return_expr) {
                    fprintf(stderr,"Semantic Error: Missing return in non-khali function 'mukkho' at line %d\n", line_num);
                    exit(1);
                }
            }

            func_register(f); $$=NULL;
        }
    ;

param_list_opt
    : /* empty */ { $$ = NULL; }
    | param_list  { $$ = $1;   }
    ;

param_list
    : param                     { $$ = $1; }
    | param_list COMMA param    { $$ = node_append($1,$3); }
    ;

param
    : IDENTIFIER COLON type
        { ASTNode *n=new_node(N_PARAM); n->sval=$1; n->vtype=$3; $$=n; }
    | IDENTIFIER COLON TYPE_TALIKA LT elem_type GT
        { ASTNode *n=new_node(N_PARAM); n->sval=$1; n->vtype=T_ARRAY; n->elem_vtype=$5; $$=n; }
    ;

type
    : TYPE_PURNO      { $$=T_INT;    }
    | TYPE_DOSHOMIK   { $$=T_DOUBLE; }
    | TYPE_OKKHOR     { $$=T_CHAR;   }
    | TYPE_BOOL       { $$=T_BOOL;   }
    | TYPE_KHALI      { $$=T_VOID;   }
    | TYPE_OKKHORMALA { $$=T_STRING; }
    ;

elem_type
    : TYPE_PURNO      { $$=T_INT;    }
    | TYPE_DOSHOMIK   { $$=T_DOUBLE; }
    | TYPE_OKKHOR     { $$=T_CHAR;   }
    | TYPE_BOOL       { $$=T_BOOL;   }
    | TYPE_OKKHORMALA { $$=T_STRING; }
    ;

block
    : LBRACE stmt_list RBRACE
        { ASTNode *n=new_node(N_BLOCK); n->c0=$2; $$=n; }
    ;

stmt_list
    : /* empty */       { $$ = NULL; }
    | stmt_list stmt    { $$ = node_append($1,$2); }
    ;

stmt
    : var_decl              { $$ = $1; }
    | expr SEMICOLON        { $$ = $1; }
    | if_stmt               { $$ = $1; }
    | for_stmt              { $$ = $1; }
    | while_stmt            { $$ = $1; }
    | switch_stmt           { $$ = $1; }
    | return_stmt SEMICOLON { $$ = $1; }
    | THAMO SEMICOLON       { $$ = new_node(N_BREAK);    }
    | CHOLTETHAKO SEMICOLON { $$ = new_node(N_CONTINUE); }
    | io_stmt SEMICOLON     { $$ = $1; }
    ;

/* ----  Variable Declarations  ----
   All rules use id_list to avoid shift/reduce conflict on COLON
   ---------------------------------------------------------------- */
var_decl
    : id_list COLON type SEMICOLON
        { ASTNode *n=new_node(N_VAR_DECL); n->c0=$1; n->c1=NULL; n->vtype=$3; $$=n; }
    | id_list COLON type ASSIGN expr_list SEMICOLON
        { ASTNode *n=new_node(N_VAR_DECL); n->c0=$1; n->c1=$5; n->vtype=$3; $$=n; }
    | id_list COLON TYPE_TALIKA LT elem_type GT SEMICOLON
        {
            /* For array decl via id_list, only single name allowed (checked semantically) */
            if ($1 && $1->next) {
                fprintf(stderr,"Semantic Error: Array declaration supports only one identifier at line %d\n", line_num);
                exit(1);
            }
            ASTNode *n=new_node(N_ARRAY_DECL);
            n->sval=$1->sval; n->vtype=T_ARRAY; n->elem_vtype=$5; n->c0=NULL; $$=n;
        }
    | id_list COLON TYPE_TALIKA LT elem_type GT ASSIGN LBRACKET elem_list_opt RBRACKET SEMICOLON
        {
            if ($1 && $1->next) {
                fprintf(stderr,"Semantic Error: Array declaration supports only one identifier at line %d\n", line_num);
                exit(1);
            }
            ASTNode *n=new_node(N_ARRAY_DECL);
            n->sval=$1->sval; n->vtype=T_ARRAY; n->elem_vtype=$5; n->c0=$9; $$=n;
        }
    ;

id_list
    : IDENTIFIER
        { ASTNode *n=new_node(N_IDENT); n->sval=$1; $$=n; }
    | id_list COMMA IDENTIFIER
        { ASTNode *n=new_node(N_IDENT); n->sval=$3; $$=node_append($1,n); }
    ;

expr_list
    : expr                    { $$ = $1; }
    | expr_list COMMA expr    { $$ = node_append($1,$3); }
    ;

elem_list_opt
    : /* empty */ { $$ = NULL; }
    | elem_list   { $$ = $1;   }
    ;

elem_list
    : expr                  { $$ = $1; }
    | elem_list COMMA expr  { $$ = node_append($1,$3); }
    ;

/* ---- Conditionals ---- */

if_stmt
    : JODI LPAREN expr RPAREN block else_part
        { ASTNode *n=new_node(N_IF); n->c0=$3; n->c1=$5; n->c2=$6; $$=n; }
    ;

else_part
    : /* empty */  { $$ = NULL; }
    | NAHOLEJODI LPAREN expr RPAREN block else_part
        { ASTNode *n=new_node(N_IF); n->c0=$3; n->c1=$5; n->c2=$6; $$=n; }
    | NAHOLE block
        { $$ = $2; }
    ;

/* ---- For loop  ---- */

for_stmt
    : GHURAO LPAREN for_init SEMICOLON expr SEMICOLON for_update RPAREN block
        { ASTNode *n=new_node(N_FOR); n->c0=$3; n->c1=$5; n->c2=$7; n->c3=$9; $$=n; }
    | GHURAO LPAREN for_init SEMICOLON expr SEMICOLON RPAREN block
        { ASTNode *n=new_node(N_FOR); n->c0=$3; n->c1=$5; n->c2=NULL; n->c3=$8; $$=n; }
    | GHURAO LPAREN for_init SEMICOLON SEMICOLON for_update RPAREN block
        { ASTNode *n=new_node(N_FOR); n->c0=$3; n->c1=NULL; n->c2=$6; n->c3=$8; $$=n; }
    ;

for_decl_init
    : id_list COLON type
        { ASTNode *n=new_node(N_VAR_DECL); n->c0=$1; n->c1=NULL; n->vtype=$3; $$=n; }
    | id_list COLON type ASSIGN expr_list
        { ASTNode *n=new_node(N_VAR_DECL); n->c0=$1; n->c1=$5; n->vtype=$3; $$=n; }
    | id_list COLON TYPE_TALIKA LT elem_type GT
        {
            if ($1 && $1->next) {
                fprintf(stderr,"Semantic Error: Array declaration supports only one identifier at line %d\n", line_num);
                exit(1);
            }
            ASTNode *n=new_node(N_ARRAY_DECL);
            n->sval=$1->sval; n->vtype=T_ARRAY; n->elem_vtype=$5; n->c0=NULL; $$=n;
        }
    | id_list COLON TYPE_TALIKA LT elem_type GT ASSIGN LBRACKET elem_list_opt RBRACKET
        {
            if ($1 && $1->next) {
                fprintf(stderr,"Semantic Error: Array declaration supports only one identifier at line %d\n", line_num);
                exit(1);
            }
            ASTNode *n=new_node(N_ARRAY_DECL);
            n->sval=$1->sval; n->vtype=T_ARRAY; n->elem_vtype=$5; n->c0=$9; $$=n;
        }
    ;

for_init
    : /* empty */ { $$ = NULL; }
    | expr        { $$ = $1;   }
    | for_decl_init { $$ = $1; }
    ;

for_update
    : expr { $$ = $1; }
    ;

/* ---- While loop ---- */

while_stmt
    : JOTOKKHON LPAREN expr RPAREN block
        { ASTNode *n=new_node(N_WHILE); n->c0=$3; n->c1=$5; $$=n; }
    ;

/* ---- Switch ---- */

switch_stmt
    : NIRBACHON LPAREN expr RPAREN LBRACE case_list RBRACE
        {
            validate_switch_case_defaults($6, line_num);
            ASTNode *n=new_node(N_SWITCH); n->c0=$3; n->c1=$6; $$=n;
        }
    ;

case_list
    : case_clause              { $$ = $1; }
    | case_list case_clause    { $$ = node_append($1,$2); }
    ;

case_clause
    : DHORO expr COLON stmt_list
        { ASTNode *n=new_node(N_CASE); n->ival=0; n->c0=$2; n->c1=$4; $$=n; }
    | ONNOTHA COLON stmt_list
        { ASTNode *n=new_node(N_CASE); n->ival=1; n->c0=NULL; n->c1=$3; $$=n; }
    ;

/* ---- Return ---- */

return_stmt
    : FERAO expr  { ASTNode *n=new_node(N_RETURN); n->c0=$2; $$=n; }
    | FERAO       { $$ = new_node(N_RETURN_VOID); }
    ;

/* ---- I/O Statements ---- */

io_stmt
    : DEKHAO LPAREN arg_list RPAREN
        { ASTNode *n=new_node(N_DEKHAO); n->ival=0; n->c0=$3; $$=n; }
    | DEKHAOLINE LPAREN arg_list RPAREN
        { ASTNode *n=new_node(N_DEKHAO); n->ival=1; n->c0=$3; $$=n; }
    | NAO LPAREN IDENTIFIER RPAREN
        { ASTNode *id=new_node(N_IDENT); id->sval=$3; ASTNode *n=new_node(N_NAO); n->c0=id; $$=n; }
    ;

/* ---- Expressions ---- */

expr
    : INT_LITERAL     { ASTNode *n=new_node(N_INT_LIT);   n->ival=$1; $$=n; }
    | DECIMAL_LITERAL { ASTNode *n=new_node(N_FLOAT_LIT); n->dval=$1; $$=n; }
    | CHAR_LITERAL    { ASTNode *n=new_node(N_CHAR_LIT);  n->cval=$1; $$=n; }
    | STRING_LITERAL  { ASTNode *n=new_node(N_STR_LIT);   n->sval=$1; $$=n; }
    | TRUE_LITERAL    { ASTNode *n=new_node(N_BOOL_LIT);  n->ival=1;  $$=n; }
    | FALSE_LITERAL   { ASTNode *n=new_node(N_BOOL_LIT);  n->ival=0;  $$=n; }

    | IDENTIFIER
        { ASTNode *n=new_node(N_IDENT); n->sval=$1; $$=n; }

    | IDENTIFIER LPAREN arg_list_opt RPAREN
        { ASTNode *n=new_node(N_FUNC_CALL); n->sval=$1; n->c0=$3; $$=n; }

    /* Math built-ins */
    | SIN LPAREN expr RPAREN        { ASTNode *n=new_node(N_FUNC_CALL); n->sval=strdup("sin");        n->c0=$3; $$=n; }
    | COS LPAREN expr RPAREN        { ASTNode *n=new_node(N_FUNC_CALL); n->sval=strdup("cos");        n->c0=$3; $$=n; }
    | TAN LPAREN expr RPAREN        { ASTNode *n=new_node(N_FUNC_CALL); n->sval=strdup("tan");        n->c0=$3; $$=n; }
    | LOG LPAREN expr RPAREN        { ASTNode *n=new_node(N_FUNC_CALL); n->sval=strdup("log");        n->c0=$3; $$=n; }
    | LOG10 LPAREN expr RPAREN      { ASTNode *n=new_node(N_FUNC_CALL); n->sval=strdup("log10");      n->c0=$3; $$=n; }
    | UPOREPURNO LPAREN expr RPAREN { ASTNode *n=new_node(N_FUNC_CALL); n->sval=strdup("uporePurno"); n->c0=$3; $$=n; }
    | NICHEPURNO LPAREN expr RPAREN { ASTNode *n=new_node(N_FUNC_CALL); n->sval=strdup("nichePurno"); n->c0=$3; $$=n; }
    | BORGOMUL LPAREN expr RPAREN   { ASTNode *n=new_node(N_FUNC_CALL); n->sval=strdup("borgomul");   n->c0=$3; $$=n; }
    | POROM LPAREN expr RPAREN      { ASTNode *n=new_node(N_FUNC_CALL); n->sval=strdup("porom");      n->c0=$3; $$=n; }

    /* Indexing */
    | expr LBRACKET expr RBRACKET
        { ASTNode *n=new_node(N_ARRAY_ACCESS); n->c0=$1; n->c1=$3; $$=n; }

    /* .dairgho() */
    | expr DOT DAIRGHO LPAREN RPAREN
        { ASTNode *n=new_node(N_DOT_DAIRGHO); n->c0=$1; $$=n; }

    /* Parenthesised */
    | LPAREN expr RPAREN { $$ = $2; }

    /* Assignment operators (lhs must be lvalue, checked at runtime) */
    | expr ASSIGN      expr { ASTNode *n=new_node(N_ASSIGN);           n->c0=$1; n->c1=$3; n->op='='; $$=n; }
    | expr PLUS_ASSIGN  expr { ASTNode *n=new_node(N_COMPOUND_ASSIGN); n->c0=$1; n->c1=$3; n->op='+'; $$=n; }
    | expr MINUS_ASSIGN expr { ASTNode *n=new_node(N_COMPOUND_ASSIGN); n->c0=$1; n->c1=$3; n->op='-'; $$=n; }
    | expr MULT_ASSIGN  expr { ASTNode *n=new_node(N_COMPOUND_ASSIGN); n->c0=$1; n->c1=$3; n->op='*'; $$=n; }
    | expr DIV_ASSIGN   expr { ASTNode *n=new_node(N_COMPOUND_ASSIGN); n->c0=$1; n->c1=$3; n->op='/'; $$=n; }
    | expr MOD_ASSIGN   expr { ASTNode *n=new_node(N_COMPOUND_ASSIGN); n->c0=$1; n->c1=$3; n->op='%'; $$=n; }

    /* Binary arithmetic */
    | expr PLUS     expr { ASTNode *n=new_node(N_BINARY); n->op='+'; n->c0=$1; n->c1=$3; $$=n; }
    | expr MINUS    expr { ASTNode *n=new_node(N_BINARY); n->op='-'; n->c0=$1; n->c1=$3; $$=n; }
    | expr MULTIPLY expr { ASTNode *n=new_node(N_BINARY); n->op='*'; n->c0=$1; n->c1=$3; $$=n; }
    | expr DIVIDE   expr { ASTNode *n=new_node(N_BINARY); n->op='/'; n->c0=$1; n->c1=$3; $$=n; }
    | expr MODULO   expr { ASTNode *n=new_node(N_BINARY); n->op='%'; n->c0=$1; n->c1=$3; $$=n; }
    | expr POWER    expr { ASTNode *n=new_node(N_BINARY); n->op='P'; n->c0=$1; n->c1=$3; $$=n; }

    /* Relational */
    | expr LT expr { ASTNode *n=new_node(N_BINARY); n->op='<'; n->c0=$1; n->c1=$3; $$=n; }
    | expr GT expr { ASTNode *n=new_node(N_BINARY); n->op='>'; n->c0=$1; n->c1=$3; $$=n; }
    | expr LE expr { ASTNode *n=new_node(N_BINARY); n->op='L'; n->c0=$1; n->c1=$3; $$=n; }
    | expr GE expr { ASTNode *n=new_node(N_BINARY); n->op='G'; n->c0=$1; n->c1=$3; $$=n; }
    | expr EQ expr { ASTNode *n=new_node(N_BINARY); n->op='E'; n->c0=$1; n->c1=$3; $$=n; }
    | expr NE expr { ASTNode *n=new_node(N_BINARY); n->op='N'; n->c0=$1; n->c1=$3; $$=n; }

    /* Logical */
    | expr AND expr { ASTNode *n=new_node(N_BINARY); n->op='A'; n->c0=$1; n->c1=$3; $$=n; }
    | expr OR  expr { ASTNode *n=new_node(N_BINARY); n->op='O'; n->c0=$1; n->c1=$3; $$=n; }

    /* Bitwise */
    | expr BIT_AND    expr { ASTNode *n=new_node(N_BINARY); n->op='&'; n->c0=$1; n->c1=$3; $$=n; }
    | expr BIT_OR     expr { ASTNode *n=new_node(N_BINARY); n->op='|'; n->c0=$1; n->c1=$3; $$=n; }
    | expr BIT_XOR    expr { ASTNode *n=new_node(N_BINARY); n->op='^'; n->c0=$1; n->c1=$3; $$=n; }
    | expr LEFT_SHIFT  expr { ASTNode *n=new_node(N_BINARY); n->op='S'; n->c0=$1; n->c1=$3; $$=n; }
    | expr RIGHT_SHIFT expr { ASTNode *n=new_node(N_BINARY); n->op='R'; n->c0=$1; n->c1=$3; $$=n; }

    /* Unary */
    | MINUS expr %prec UMINUS  { ASTNode *n=new_node(N_UNARY); n->op='-'; n->c0=$2; $$=n; }
    | PLUS  expr %prec UPLUS   { ASTNode *n=new_node(N_UNARY); n->op='+'; n->c0=$2; $$=n; }
    | NOT   expr %prec UNOT    { ASTNode *n=new_node(N_UNARY); n->op='!'; n->c0=$2; $$=n; }
    | BIT_NOT expr %prec UBITNOT { ASTNode *n=new_node(N_UNARY); n->op='~'; n->c0=$2; $$=n; }

    /* Postfix */
    | expr INCREMENT { ASTNode *n=new_node(N_POSTFIX_INC); n->c0=$1; $$=n; }
    | expr DECREMENT { ASTNode *n=new_node(N_POSTFIX_DEC); n->c0=$1; $$=n; }

    /* Prefix */
    | INCREMENT expr { ASTNode *n=new_node(N_PREFIX_INC); n->c0=$2; $$=n; }
    | DECREMENT expr { ASTNode *n=new_node(N_PREFIX_DEC); n->c0=$2; $$=n; }

    /* Array literal */
    | LBRACKET elem_list_opt RBRACKET
        { ASTNode *n=new_node(N_ARRAY_LIT); n->c0=$2; $$=n; }
    ;

arg_list_opt
    : /* empty */ { $$ = NULL; }
    | arg_list    { $$ = $1;   }
    ;

arg_list
    : expr                  { $$ = $1; }
    | arg_list COMMA expr   { $$ = node_append($1,$3); }
    ;

%%

void yyerror(const char *s) {
    fprintf(stderr, "Syntax Error: %s at line %d\n", s, line_num);
    exit(1);
}
