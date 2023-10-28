#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

// Read file

/*
XXXXXXXX | XX  XXX XXX
100010DW | MOD REG R/M
*/

const int MAX_BYTES = 512;

int read_file(const char *fname);

void parse_byte1(uint8_t byte, uint8_t *W, uint8_t *D, char *out)
{
    // first 6 bytes determine operand
    uint8_t opcode = byte >> 2;
    // 2nd last byte
    *D = (byte & 0x02) >> 1;
    // last byte
    *W = (byte & 0x01);
    if (opcode == 0b100010)
    {
        sprintf(out, "mov");
    }
    // printf("%x: %s %d %d\n", byte, op, *D, *W);
}

void parse_reg(uint8_t byte, uint8_t W, char out[3])
{
    if (byte == 0 || (byte == 4 && W == 0))
        out[0] = 'a';
    else if (byte == 1 || (byte == 5 && W == 0))
        out[0] = 'c';
    else if (byte == 2 || (byte == 6 && W == 0))
        out[0] = 'd';
    else if (byte == 3 || (byte == 7 && W == 0))
        out[0] = 'b';
    else if (W == 1)
    {
        if (byte == 4)
            out[0] = 's';
        if (byte == 5)
            out[0] = 'b';
        if (byte == 6)
            out[0] = 's';
        if (byte == 7)
            out[0] = 'd';
    }
    /* out[1]*/
    if (W == 0)
    {
        if (byte < 4)
            out[1] = 'l';
        else
            out[1] = 'h';
    }
    if (W == 1)
    {
        if (byte < 4)
            out[1] = 'x';
        else if (byte < 6)
            out[1] = 'p';
        else
            out[1] = 'i';
    }
    out[2] = '\0';
}

void parse_byte2(u_int8_t byte, uint8_t W, uint8_t D, char out[])
{
    // ABXXXXXX: first 2 bytes
    uint8_t MOD = byte >> 6;
    // XXABCXXX: bytes 3-5
    uint8_t REG = (byte >> 3) & 0x07;
    // XXXXXABC: last 3 bytes
    uint8_t RM = byte & 0x07;
    char regout[3];
    char rmout[3];
    /* regout */
    parse_reg(REG, W, regout);
    // TODO consider MOD
    // rmout
    if (MOD == 3)
    {
        // same logic as reg
        parse_reg(RM, W, rmout);
    }
    // if D regout, rmout else rmout, regout
    if (D)
        sprintf(out, "%s, %s", regout, rmout);
    else
        sprintf(out, "%s, %s", rmout, regout);
    // printf("%d: %d %d %s %d %s\n", byte, MOD, REG, regout, RM, rmout);
}

int main(int argc, char *argv[])
{
    if (argc < 2)
    {
        fprintf(stderr, "Usage: %s filename\n", argv[0]);
        return 2;
    }
    const char *fname = argv[1];
    if (read_file(fname))
    {
        fprintf(stderr, "Failed to read file\n");
    }
}

int read_file(const char *fname)
{
    int is_ok = EXIT_FAILURE;

    FILE *fp = fopen(fname, "r+");
    if (!fp)
    {
        perror("File opening failed");
        return is_ok;
    }

    int c, i = 0; // note: int, not char, required to handle EOF
    uint8_t W, D = 0;
    char opout[4];
    char rout[8];
    char lineout[14];
    puts("bits 16\n");
    while ((c = fgetc(fp)) != EOF)
    {        
        switch (i % 2)
        {
        case 0:
            parse_byte1(c, &W, &D, opout);
            break;
        case 1:
            parse_byte2(c, W, D, rout);
            sprintf(lineout, "%s %s", opout, rout);
            puts(lineout);
            break;
        }
        i++;
    }
    puts("");
    if (ferror(fp))
        puts("I/O error when reading");
    else if (feof(fp))
    {
        is_ok = EXIT_SUCCESS;
    }

    fclose(fp);
    return is_ok;
}
