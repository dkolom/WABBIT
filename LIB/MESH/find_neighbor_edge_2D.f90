!> \file
!> \callgraph
! ********************************************************************************************
! WABBIT
! ============================================================================================
!> \name find_neighbor_edge_2D.f90
!> \version 0.4
!> \author msr
!
!> \brief find neighbor on block edge
!> \details valid cases for edge neighbors:
!!           1. same level: always exact one neighbor
!!           2. one level down: one neighbor, two possible
!! neighbor relations
!!           3. one level up: always two neighbors
!!
!! input:
!!           - heavy and light data id
!!           - light data array and max treelevel
!!           - direction for neighbor search
!!           - list of active blocks
!!
!! output:
!!           - neighbor list array
!!
! -------------------------------------------------------------------------------------------------------------------------
!> \details
!! dirs = (/'__N', '__E', '__S', '__W', '_NE', '_NW', '_SE', '_SW', 'NNE', 'NNW', 'SSE', 'SSW', 'ENE', 'ESE', 'WNW', 'WSW'/)
!!
!!
!! \date 7/11/16 - switch to v0.4
!! \date 12/02/19 - update neighbor search for multipile trees (PKrah)
! ********************************************************************************************
!> \image html neighborhood.svg "Neighborhood Relations in 2D" width=400

subroutine find_neighbor_edge_2D(params, heavy_id, light_id, lgt_block, &
            max_treelevel, dir, hvy_neighbor, lgt_n, lgt_sortednumlist, error, n_domain)
    implicit none
    !> user defined parameter structure
    type (type_params), intent(in)      :: params
    !> heavy data id
    integer(kind=ik), intent(in)        :: heavy_id
    !> light data id
    integer(kind=ik), intent(in)        :: light_id
    !> max treelevel
    integer(kind=ik), intent(in)        :: max_treelevel
    !> light data array
    integer(kind=ik), intent(in)        :: lgt_block(:, :)
    !> direction for neighbor search
    character(len=3), intent(in)        :: dir
    !> number of active blocks (light data)
    integer(kind=ik), intent(in)        :: lgt_n
    !> sorted list of numerical treecodes, used for block finding
    integer(kind=tsize), intent(in)     :: lgt_sortednumlist(:,:)
    !> heavy data array - neighbor data
    integer(kind=ik), intent(inout)     :: hvy_neighbor(:,:)
    logical, intent(inout)              :: error
    integer(kind=2), intent(in) :: n_domain(1:3)

    ! auxiliary variables
    integer(kind=ik)                    :: neighborID_sameLevel, virt_code1, neighborID_finerLevel1, virt_code2, neighborID_finerLevel2, neighborID_coarserLevel

    ! mesh level
    integer(kind=ik)                    :: level
    ! treecode varaibles
    integer(kind=ik)                    :: my_treecode(max_treelevel), neighbor(max_treelevel), virt_treecode(max_treelevel)
    ! return value from function "does_block_exist"
    logical                             :: exists
    ! neighbor light data id, and id of the tree in the forest
    integer(kind=ik)                    :: neighbor_light_id, tree_id

    my_treecode = lgt_block( light_id, 1:max_treelevel )
    level      = lgt_block( light_id, max_treelevel + IDX_MESH_LVL )
    tree_id    = lgt_block( light_id, max_treelevel + IDX_TREE_ID )
    neighborID_sameLevel    = -1
    virt_code1              = -1
    neighborID_finerLevel1  = -1
    virt_code2              = -1
    neighborID_finerLevel2  = -1
    neighborID_coarserLevel = -1


    ! set virt_code and lvl_down_neighbor
    select case(dir)
        case('__N')
            neighborID_sameLevel    = 1
            ! virtual treecodes, list_ids for neighbors on higher level
            virt_code1    = 0
            neighborID_finerLevel1 = 10
            virt_code2    = 1
            neighborID_finerLevel2 = 9
            ! id2 for cases with neighbor one level down
            if ( lgt_block(light_id, level) == 0) then
                neighborID_coarserLevel = 10
            elseif ( lgt_block(light_id, level) == 1) then
                neighborID_coarserLevel = 9
            end if

        case('__E')
            neighborID_sameLevel = 2
            ! virtual treecodes for neighbors on higher level
            virt_code1    = 1
            neighborID_finerLevel1 = 13
            virt_code2    = 3
            neighborID_finerLevel2 = 14
            ! id2 for cases with neighbor one level down
            if ( lgt_block(light_id, level) == 1) then
                neighborID_coarserLevel = 13
            elseif ( lgt_block(light_id, level) == 3) then
                neighborID_coarserLevel = 14
            end if

        case('__S')
            neighborID_sameLevel   = 3
            ! virtual treecodes for neighbors on higher level
            virt_code1    = 2
            neighborID_finerLevel1 = 12
            virt_code2    = 3
            neighborID_finerLevel2 = 11
            ! id2 for cases with neighbor one level down
            if ( lgt_block(light_id, level) == 3) then
                neighborID_coarserLevel = 11
            elseif ( lgt_block(light_id, level) == 2) then
                neighborID_coarserLevel = 12
            end if

        case('__W')
            neighborID_sameLevel   = 4
            ! virtual treecodes for neighbors on higher level
            virt_code1    = 0
            neighborID_finerLevel1 = 15
            virt_code2    = 2
            neighborID_finerLevel2 = 16
            ! id2 for cases with neighbor one level down
            if ( lgt_block(light_id, level) == 0) then
                neighborID_coarserLevel = 15
            elseif ( lgt_block(light_id, level) == 2) then
                neighborID_coarserLevel = 16
            end if

    end select

    ! calculate treecode for neighbor on same level
    call adjacent_block_2D( my_treecode, neighbor, dir, level, max_treelevel)
    ! check existence of neighbor block and find light data id
    call does_block_exist(neighbor, exists, neighbor_light_id, lgt_sortednumlist, lgt_n, tree_id)


    if (exists) then
        ! neighbor on same level
        ! write neighbor data, 2D: 16 possible neighbor relations
        hvy_neighbor( heavy_id, neighborID_sameLevel ) = neighbor_light_id
    else

        ! neighbor could be one level down
        neighbor( level ) = -1
        ! check existence of neighbor block
        call does_block_exist(neighbor, exists, neighbor_light_id, &
                             lgt_sortednumlist, lgt_n, tree_id)

        if ( exists ) then
            ! neigbor is one level down
            ! save neighborID_coarserLevel
            hvy_neighbor( heavy_id, neighborID_coarserLevel ) = neighbor_light_id

        elseif ( .not.(exists) .and. (level/=params%max_treelevel)) then
            ! 2 neighbors one level up

            ! first neighbor virtual treecode, one level up
            virt_treecode = my_treecode
            virt_treecode( level+1 ) = virt_code1

            ! calculate treecode for neighbor on same level (virtual level)
            call adjacent_block_2D( virt_treecode, neighbor, dir, level+1, max_treelevel)
            ! check existence of neighbor block
            call does_block_exist(neighbor, exists, neighbor_light_id, lgt_sortednumlist, lgt_n, tree_id)

            if (exists) then
                ! neigbor is one level up
                ! write data
                hvy_neighbor( heavy_id, neighborID_finerLevel1 ) = neighbor_light_id
            end if

            ! we did not find a neighbor. that may be a bad grid error, or simply, there is none
            ! because symmetry conditions are used.
            if ((.not. exists .and. ALL(params%periodic_BC)).or.(maxval(abs(n_domain))==0.and..not.exists)) then
                write(*,*) "Edge neighbor not found"
                error = .true.
            endif

            ! second neighbor virtual treecode, one level up
            virt_treecode = my_treecode
            virt_treecode( level+1 ) = virt_code2

            ! calculate treecode for neighbor on same level (virtual level)
            call adjacent_block_2D( virt_treecode, neighbor, dir, level+1, max_treelevel)
            ! check existence of neighbor block
            call does_block_exist(neighbor, exists, neighbor_light_id, lgt_sortednumlist, lgt_n, tree_id)

            if (exists) then
                ! neigbor is one level up
                ! write data
                hvy_neighbor( heavy_id, neighborID_finerLevel2 ) = neighbor_light_id
            end if

        end if

    end if

end subroutine find_neighbor_edge_2D
