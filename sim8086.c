#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

// Read file

/*
XXXXXXXX | XX  XXX XXX
100010DW | MOD REG R/M
*/

const int MAX_BYTES = 512;

int read_file(const char *fname);

void parse_byte1(uint8_t byte)
{
    // first 6 bytes determine operand
    uint8_t opcode = byte >> 2;
    // 2nd last byte
    uint8_t D = (byte & 0x02) >> 1;
    // last byte
    uint8_t W = (byte & 0x01);
    char *op = "";
    if (opcode == 0b100010)
    {
        op = "mov";
    }
    printf("%x: %s %d %d\n", byte, op, D, W);
}

void parse_byte2(u_int8_t byte, uint8_t D, uint8_t W)
{
    // ABXXXXXX: first 2 bytes
    uint8_t MOD = byte >> 6;
    // XXABCXXX: bytes 3-5
    uint8_t REG = (byte >> 3) & 0x07;
    // XXXXXABC: last 3 bytes
    uint8_t RM = byte & 0x07;
    char regout[2];
    /* regout[0] */
    if (REG == 0 || (REG == 4 && W == 0))
        regout[0] = 'A';
    else if (REG == 1 || (REG == 5 && W == 0))
        regout[0] = 'C';
    else if (REG == 2 || (REG == 6 && W == 0))
        regout[0] = 'D';
    else if (REG == 3 || (REG == 7 && W == 0))
        regout[0] = 'B';
    else if (W == 1)
    {
        if (REG == 4)
            regout[0] = 'S';
        if (REG == 4)
            regout[0] = 'B';
        if (REG == 4)
            regout[0] = 'S';
        if (REG == 4)
            regout[0] = 'D';
    }
    /* regout[1]*/
    if (W == 0)
    {
        if (REG < 4)
            regout[1] = 'L';
        else
            regout[1] = 'H';
    }
    if (W == 1)
    {
        if (REG < 4)
            regout[1] = 'X';
        else if (REG < 6)
            regout[1] = 'P';
        else
            regout[1] = 'I';
    }

    printf("%d: %d %d %s %d\n", byte, MOD, REG, regout, RM);
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
    while ((c = fgetc(fp)) != EOF)
    {
        if (c == '\n')
        {
            i = 0;
            continue;
        }
        switch (i)
        {
        case 0:
            parse_byte1(c);
            break;
        case 1:
            parse_byte2(c, 0, 0);
            break;
        }
        i++;
    }
    if (ferror(fp))
        puts("I/O error when reading");
    else if (feof(fp))
    {
        puts("End of file is reached successfully");
        is_ok = EXIT_SUCCESS;
    }

    fclose(fp);
    return is_ok;
}
