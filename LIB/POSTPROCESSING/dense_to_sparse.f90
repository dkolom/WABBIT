
!> \file
!> \name sparse_to_dense.f90
!> \author PKrah
!> \brief postprocessing for sparsing data from a dense wabbit field
!> \date 29.03.2019 creation
!-----------------------------------------------------------------------------------------------------

subroutine dense_to_sparse(params)
    use module_precision
    use module_mesh
    use module_params
    use module_IO
    use module_mpi
    use module_initialization
    use module_helpers

    implicit none

    !> parameter struct
    type (type_params), intent(inout)  :: params
    character(len=80)      :: indicator="threshold-state-vector", file_in, args
    character(len=80)      :: tail_string
    real(kind=rk)          :: time, eps=-1.0_rk
    integer(kind=ik)       :: iteration
    character(len=80), allocatable :: file_out(:)
    integer(kind=ik), allocatable           :: lgt_block(:, :)
    real(kind=rk), allocatable              :: hvy_block(:, :, :, :, :), hvy_work(:, :, :, :, :, :)
    real(kind=rk), allocatable              :: hvy_tmp(:, :, :, :, :)
    integer(kind=ik), allocatable           :: hvy_neighbor(:,:)
    integer(kind=ik), allocatable           :: lgt_active(:,:), hvy_active(:,:), hvy_n(:), lgt_n(:)
    integer(kind=tsize), allocatable        :: lgt_sortednumlist(:,:,:)
    integer(kind=ik)                        :: max_neighbors, level, k, tc_length, lgt_n_tmp
    integer(kind=ik), dimension(3)          :: Bs
    integer(hid_t)                          :: file_id
    character(len=2)                        :: level_in
    character(len=80)                       :: order
    real(kind=rk), dimension(3)             :: domain
    integer(hsize_t), dimension(2)          :: dims_treecode
    integer(kind=ik)                        :: treecode_size, number_dense_blocks, i, l, dim
    !-----------------------------------------------------------------------------------------------------

    call get_command_argument(2, file_in)
    if (file_in == '--help' .or. file_in == '--h') then
        if ( params%rank==0 ) then
            write(*,*) "--------------------------------------------------------------"
            write(*,*) "                DENSE TO SPARSE "
            write(*,*) "--------------------------------------------------------------"
            write(*,*) "postprocessing subroutine sparse a mesh with a given detail treshold"
            write(*,*) " "
            write(*,*) "Command:"
            write(*,*) "./wabbit-post --dense-to-sparse "
            write(*,*) "-------------------------------------------------------------"
            write(*,*) " Parameters: "
            write(*,*) "  --eps-normalized="
            write(*,*) "  --eps-norm="
            write(*,*) "  --eps="
            write(*,*) "  --indicator="
            write(*,*) "  --order="
            write(*,*) "  --files="
            write(*,*) "-------------------------------------------------------------"
            write(*,*)
        end if
        return
    end if

    !----------------------------------
    ! read parameters
    !----------------------------------
    call get_cmd_arg_bool( "--eps-normalized", params%eps_normalized, default=.true. )
    call get_cmd_arg_str( "--eps-norm", params%eps_norm, default="L2" )
    call get_cmd_arg_dbl( "--eps", params%eps, default=-1.0_rk )
    call get_cmd_arg_str( "--indicator", indicator, default="threshold-state-vector" )
    call get_cmd_arg_str( "--order", order, default="CDF40" )
    call get_cmd_arg_str_vct( "--files", params%input_files )


    ! Check parameters for correct inputs:
    if (order == "CDF20") then
        params%harten_multiresolution = .true.
        params%order_predictor = "multiresolution_2nd"
        params%n_ghosts = 2_ik
    elseif (order == "CDF40") then
        params%harten_multiresolution = .true.
        params%order_predictor = "multiresolution_4th"
        params%n_ghosts = 4_ik
    elseif (order == "CDF44") then
        params%harten_multiresolution = .false.
        params%wavelet_transform_type = 'biorthogonal'
        params%order_predictor = "multiresolution_4th"
        params%wavelet='CDF4,4'
        params%n_ghosts = 6_ik
    else
        call abort(20030202, "The --order parameter is not correctly set [CDF40, CDF20, CDF44]")
    end if

    if (params%eps < 0.0_rk) then
        call abort(2303191,"You must specify the threshold value --eps")
    endif

    params%coarsening_indicator = indicator
    params%forest_size = 1

    params%n_eqn = size(params%input_files)
    allocate(params%field_names(params%n_eqn))
    allocate(file_out(params%n_eqn))
    allocate(params%threshold_state_vector_component(params%n_eqn))
    params%threshold_state_vector_component = .true.

    !-------------------------------------------
    ! check and find common params in all h5-files
    !-------------------------------------------
    call read_attributes(params%input_files(1), lgt_n_tmp, time, iteration, params%domain_size, &
    params%Bs,params%max_treelevel, params%dim, periodic_BC=params%periodic_BC, symmetry_BC=params%symmetry_BC)

    do i = 1, params%n_eqn
        file_in = params%input_files(i)
        call check_file_exists(trim(file_in))
        call read_attributes(file_in, lgt_n_tmp, time, iteration, domain, Bs, level, dim)

        params%min_treelevel = 1
        params%max_treelevel = max(params%max_treelevel, level) ! find the maximal level of all snapshot

        if (any(params%Bs .ne. Bs)) call abort( 203192, " Block size is not consistent ")
        if (params%dim .ne. dim) call abort(243191,"Dimensions do not agree!")
        if ( abs(sum(params%domain_size(1:dim) - domain(1:dim))) > 1e-14 ) call abort( 203195, "Domain size is not consistent ")

        ! Concatenate "sparse" with filename
        params%input_files(i) = trim(file_in)
        file_out(i) = trim(file_in)
    end do

    ! in postprocessing, it is important to be sure that the parameter struct is correctly filled:
    ! most variables are unfortunately not automatically set to reasonable values. In simulations,
    ! the ini files parser takes care of that (by the passed default arguments). But in postprocessing
    ! we do not read an ini file, so defaults may not be set.
    allocate(params%butcher_tableau(1,1))


    params%block_distribution="sfc_hilbert"

    ! read attributes from file. This is especially important for the number of
    ! blocks the file contains: this will be the number of active blocks right
    ! after reading.
    if (params%dim==3) then
        ! how many blocks do we need for the desired level?
        number_dense_blocks = 8_ik**level
        max_neighbors = 74
    else
        number_dense_blocks = 4_ik**level
        max_neighbors = 12
    end if

    if (params%rank==0) then
        write(*,'(80("-"))')
        write(*,*) "Wabbit dense-to-sparse."
        do i = 1, params%n_eqn
            write(*,'(A20,1x,A80)') "Reading file:", params%input_files(i)
            write(*,'(A20,1x,A80)') "Writing to file:", file_out(i)
        end do
        write(*,'(A20,1x,A80)') "Predictor used:", params%order_predictor
        write(*,'(A20,1x,A8)') "Wavelets used:", order
        write(*,'(A20,1x,es9.3)') "eps:", params%eps
        write(*,'(A20,1x,A80)')"wavelet normalization:", params%eps_norm
        write(*,'(A20,1x,A80)')"indicator:", params%coarsening_indicator
        write(*,'(80("-"))')
    endif

    ! is lgt_n > number_dense_blocks (downsampling)? if true, allocate lgt_n blocks
    !> \todo change that for 3d case
    params%number_blocks = ceiling( 4.0*dble(max(lgt_n_tmp, number_dense_blocks)) / dble(params%number_procs) )

    if (params%rank==0) then
        write(*,'("Data dimension: ",i1,"D")') params%dim
        write(*,'("File contains Nb=",i6," blocks of size Bs=",i4," x ",i4," x ",i4)') lgt_n_tmp, Bs(1),Bs(2),Bs(3)
        write(*,'("Domain size is ",3(g12.4,1x))') domain
        write(*,'("Time=",g12.4," it=",i9)') time, iteration
        write(*,'("Length of treecodes in file=",i3," in memory=",i3)') level, params%max_treelevel
        write(*,'("NCPU=",i6)') params%number_procs
        write(*,'("File   Nb=",i6," blocks")') lgt_n_tmp
        write(*,'("Memory Nb=",i6)') params%number_blocks
        write(*,'("Dense  Nb=",i6)') number_dense_blocks
    endif

    !----------------------------------
    ! allocate data and reset grid
    !----------------------------------
    call allocate_grid(params, lgt_block, hvy_block, hvy_neighbor, lgt_active, hvy_active, &
        lgt_sortednumlist, hvy_work=hvy_work, hvy_tmp=hvy_tmp, hvy_n=hvy_n, lgt_n=lgt_n)

    ! reset the grid: all blocks are inactive and empty
    call reset_tree( params, lgt_block, lgt_active(:,tree_ID_flow), &
    lgt_n(tree_ID_flow), hvy_active(:,tree_ID_flow), hvy_n(tree_ID_flow), &
    lgt_sortednumlist(:,:,tree_ID_flow), .true., tree_ID=1 )

    ! The ghost nodes will call their own setup on the first call, but for cleaner output
    ! we can also just do it now.
    call init_ghost_nodes( params )

    !----------------------------------
    ! READ Grid and coarse if possible
    !----------------------------------
    params%adapt_mesh=.true.
    params%adapt_inicond=.true.
    params%read_from_files=.true.
    call set_initial_grid( params, lgt_block, hvy_block, hvy_neighbor, lgt_active, hvy_active, &
    lgt_n, hvy_n, lgt_sortednumlist, params%adapt_inicond, time, iteration, hvy_tmp=hvy_tmp )

    !----------------------------------
    ! Write sparse files
    !----------------------------------
    do i = 1, params%n_eqn
        call write_field(file_out(i), time, iteration, i, params, lgt_block, &
        hvy_block, lgt_active(:,tree_ID_flow), lgt_n(tree_ID_flow), hvy_n(tree_ID_flow), &
        hvy_active(:,tree_ID_flow))
    enddo

    call deallocate_grid(params, lgt_block, hvy_block, hvy_neighbor, lgt_active,&
    hvy_active, lgt_sortednumlist, hvy_work, hvy_tmp=hvy_tmp, hvy_n=hvy_n , lgt_n=lgt_n)
end subroutine dense_to_sparse
