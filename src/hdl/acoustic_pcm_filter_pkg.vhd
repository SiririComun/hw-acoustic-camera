-- Frozen phase-4 integer coefficients; generated from docs/pcm_filter_v1.json.
-- Coefficient SHA256 (LE i32): b883f094c06ee223d4c95e4bab4510d6cde5df3d889835c9c42488d1daa00d59
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
package acoustic_pcm_filter_pkg is
    subtype pcm_word is signed(31 downto 0);
    type coefficient_array is array (0 to 60) of signed(17 downto 0);
    constant C_COEFFICIENTS : coefficient_array := (
        0 => to_signed(-291, 18),
        1 => to_signed(184, 18),
        2 => to_signed(377, 18),
        3 => to_signed(719, 18),
        4 => to_signed(1236, 18),
        5 => to_signed(1960, 18),
        6 => to_signed(2932, 18),
        7 => to_signed(4191, 18),
        8 => to_signed(5775, 18),
        9 => to_signed(7720, 18),
        10 => to_signed(10054, 18),
        11 => to_signed(12800, 18),
        12 => to_signed(15969, 18),
        13 => to_signed(19560, 18),
        14 => to_signed(23561, 18),
        15 => to_signed(27945, 18),
        16 => to_signed(32669, 18),
        17 => to_signed(37678, 18),
        18 => to_signed(42901, 18),
        19 => to_signed(48255, 18),
        20 => to_signed(53648, 18),
        21 => to_signed(58976, 18),
        22 => to_signed(64133, 18),
        23 => to_signed(69010, 18),
        24 => to_signed(73499, 18),
        25 => to_signed(77497, 18),
        26 => to_signed(80910, 18),
        27 => to_signed(83656, 18),
        28 => to_signed(85669, 18),
        29 => to_signed(86896, 18),
        30 => to_signed(87306, 18),
        31 => to_signed(86896, 18),
        32 => to_signed(85669, 18),
        33 => to_signed(83656, 18),
        34 => to_signed(80910, 18),
        35 => to_signed(77497, 18),
        36 => to_signed(73499, 18),
        37 => to_signed(69010, 18),
        38 => to_signed(64133, 18),
        39 => to_signed(58976, 18),
        40 => to_signed(53648, 18),
        41 => to_signed(48255, 18),
        42 => to_signed(42901, 18),
        43 => to_signed(37678, 18),
        44 => to_signed(32669, 18),
        45 => to_signed(27945, 18),
        46 => to_signed(23561, 18),
        47 => to_signed(19560, 18),
        48 => to_signed(15969, 18),
        49 => to_signed(12800, 18),
        50 => to_signed(10054, 18),
        51 => to_signed(7720, 18),
        52 => to_signed(5775, 18),
        53 => to_signed(4191, 18),
        54 => to_signed(2932, 18),
        55 => to_signed(1960, 18),
        56 => to_signed(1236, 18),
        57 => to_signed(719, 18),
        58 => to_signed(377, 18),
        59 => to_signed(184, 18),
        60 => to_signed(-291, 18)
    );
    function rounded_pcm(acc : pcm_word) return pcm_word;
    function saturated_pcm(acc : pcm_word) return pcm_word;
    function clipped_pcm(acc : pcm_word) return std_logic;
end package;
package body acoustic_pcm_filter_pkg is
    function rounded_pcm(acc : pcm_word) return pcm_word is
        variable value : pcm_word;
    begin
        -- Arithmetic shift gives floor division; the low bits are its residue,
        -- including for negative inputs. Incrementing implements ties-to-even.
        value := shift_right(acc, 5);
        if unsigned(acc(4 downto 0)) > 16 or
           (unsigned(acc(4 downto 0)) = 16 and value(0) = '1') then
            value := value + 1;
        end if;
        return value;
    end;
    function saturated_pcm(acc : pcm_word) return pcm_word is
        variable value : pcm_word := rounded_pcm(acc);
    begin
        if value > to_signed(8388607, 32) then return to_signed(8388607, 32);
        elsif value < to_signed(-8388608, 32) then return to_signed(-8388608, 32);
        else return value;
        end if;
    end;
    function clipped_pcm(acc : pcm_word) return std_logic is
        variable value : pcm_word := rounded_pcm(acc);
    begin
        if value > to_signed(8388607, 32) or value < to_signed(-8388608, 32) then
            return '1';
        end if;
        return '0';
    end;
end package body;
