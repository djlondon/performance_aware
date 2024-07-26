# Performance Aware Programming

Work on the Performance Aware Programming Course by Casey Muratori [computerenhance.com](computerenhance.com).

Part 1

Dissambler for 8086 MOV instructions. See p160+ of the [manual](https://edge.edx.org/c4x/BITSPilani/EEE231/asset/8086_family_Users_Manual_1_.pdf).

![MOV](./images/mov.png)

Decode
  v
Simulate

Instructions implemented

| MOV     |       |        |        |   | |
|---      |---       |---         |---        |---   |--- |
|1000 10dw | mo reg rm | (DISP·LO)  | (DISP·HI) |      | |
|1100 011w | mo 000 rm | (DISP·LO)  | (DISP·HI) | data | data (w=1) |
|1011 wreg | data     | data (w=1) |           |      | |
|1010 000w | addr-lo  | addr-hi    |           | | |
|1010 001w | addr-lo  | addr-hi    |           | | |
|1000 1110 | mo 0SR r/m | (DISP·LO)  | (DISP·HI) | | |
|1000 1100 | mo 0SR r/m | (DISP·LO)  | (DISP·HI) | | |

| ADD     |       |        |        | | |
|---      |---       |---         |---        |---|---|
| 0000 00dw | mo reg r/m | (DISP-LO) | (DISP·HI) |
| 1000 00sw | mo 000 r/m | (DISP-LO) | (DISP·HI) | data | data (sw=01) |
| 0000 010w | data |     data (w=1) | | 

| SUB     |       |        |        | | |
|---      |---       |---         |---        |---|---|
| 0010 10dw | mo reg r/m | (DISP-LO) | (DISP·HI) |
| 1000 00sw | mo 101 r/m | (DISP-LO) | (DISP·HI) | data | data (sw=01) |
| 0010 110w | data   |   data (w=1) |

| CMP     |       |
|---      |---       |
| 001110dw | mo reg r/m |
| 100000sw | mo 111 r/m |
| 0011110w | data |
