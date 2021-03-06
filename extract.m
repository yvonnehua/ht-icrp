function res = extract(f, n_frm, row, col, site)
% EXTRACT  Extract single-cell data from epithelial FRET reporter cells.
%   RES = EXTRACT(F, N_FRM, ROW, COL, SITE) analyzes images in file set F
%   up to frame number N_FRM of SITE in the well at ROW and COL. Results
%   RES include FRET ratio, death metrics, and cell positions. Sam
res = struct('t', {}, 'c', {}, 'dx', {}, 'dy', {}, 'is_gap', {});
old_im = [];
jitter_scale = 0.25;
scaled_max_jitter = 10;
for frm = 1 : n_frm
    im_A = [];
    im_B = [];
    im_C = [];
    for k = 1 : length(f)
      if f(k).row == row && f(k).col == col && f(k).site == site ...
          && f(k).frm == frm
        im = single(imread(f(k).name));
        if f(k).ch == 2
          % e.g. cfp excitation, yfp emission
          im_A = bgmesh(im, 170, 128);
        elseif f(k).ch == 1
          % e.g. cfp excitation, cfp emission
          im_B = bgmesh(im, 170, 128);
        elseif f(k).ch == 3
          % this must be the rfp momp marker
          im_C = bgmesh(im, 170, 128);
        end
      end
    end
    res(frm).is_gap = false();
    if isempty(im_A) || isempty(im_B)
        res(frm) = res(frm - 1);
        res(frm).is_gap = true();
        continue
    end
    % align channels to correct for chromatic aberration
    [dx, dy] = getshift(im_A, im_B, 5);
    im_B = shiftimg(im_B, dx, dy);
    [dx, dy] = getshift(im_A, im_C, 5);
    im_C = shiftimg(im_C, dx, dy);
    % segment nuclei
    t = 5 * prctile(abs(im_C(:)), 30);
    msk = im_C > t;
    msk = bwmorph(msk, 'open', 1);
    [L, num] = bwlabel(msk);
    rp = regionprops(L, 'area', 'centroid');
    c = struct('fr', {}, 'b', {}, 'x', {}, 'y', {}, 'area', {}, ...
	       'prev', {}, 'next', {}, 'momp', {}, 'edge', {}, ...
               'rfp', {});
    for k = 1 : num
      ss_msk = (L == k);
      a = im_A(ss_msk);
      b = im_B(ss_msk);
      h2b = im_C(ss_msk);
      c(k).b = median(b);
      c(k).h2b = median(h2b);
      c(k).fr = median(a ./ b);
      c(k).x = rp(k).Centroid(1);
      c(k).y = rp(k).Centroid(2);
      if ~isempty(im_C)
        c(k).momp = momploc(im_A, im_C, ss_msk);
        c(k).rfp = prctile(im_C(ss_msk), 80);
      else
        c(k).momp = nan();
        c(k).rfp = nan();
      end
      % extract momp reporter fluorescence at thickest point of cell
      max_a = max(a);
      ss_max = (im_A == max_a) & (ss_msk);
      idx_max = find(ss_max(:), 1, 'first');
      [roi_y, roi_x] = ind2sub(size(ss_max), idx_max);
      % save area of mask
      c(k).area = rp(k).Area;
      c(k).edge = edginess(ss_msk, im_A, roi_y, roi_x);
    end
    res(frm).t = nan;
    res(frm).c = c;
    fprintf('%d / %d processed\n', frm, n_frm);
    % calculate jitter estimate
    lo_res_A = imresize(im_A, jitter_scale);
    if ~isempty(old_im)
      [dx, dy] = getshift(old_im, lo_res_A, scaled_max_jitter);
      res(frm).dx = dx / jitter_scale;
      res(frm).dy = dy / jitter_scale;
    end
    old_im = lo_res_A;
end
