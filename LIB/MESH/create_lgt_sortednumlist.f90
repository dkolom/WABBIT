!> \file
!> \callgraph
! ********************************************************************************************
! WABBIT
! ============================================================================================
!> \name create_lgt_sortednumlist.f90
!> \version 0.5
!> \author engels
!
!> \brief Create a sorted list of the numerical treecodes of all active blocks
! ********************************************************************************************

subroutine create_lgt_sortednumlist( params, lgt_block, lgt_active, lgt_n, lgt_sortednumlist )

!---------------------------------------------------------------------------------------------
! variables

    implicit none
    !> user defined parameter structure
    type (type_params), intent(in)      :: params
    !> light data array
    integer(kind=ik), intent(in)        :: lgt_block(:, :)
    !> list of active blocks (light data)
    integer(kind=ik), intent(in)       :: lgt_active(:)
    !> number of active blocks (light data)
    integer(kind=ik), intent(in)       :: lgt_n
    !
    integer(kind=tsize), intent(inout) :: lgt_sortednumlist(:,:)
    ! loop variables
    integer(kind=ik)                    :: lgt_id, j

    if (size(lgt_sortednumlist,2) /= 2 .or. size(lgt_sortednumlist,1) /= size(lgt_block,1) ) then
      call error_msg("lgt_sortednumlist is not right")
    endif

    ! init list, all inactive
    lgt_sortednumlist = -1

    ! the first step is to go through the list of active blocks, and store their
    ! numerical treecode in the array, as well as their light id. Note we compress
    ! the array directly, such that only the first lgt_n entries are used (no
    ! wholes in array usage)
    do j = 1, lgt_n
      ! get ID of an active block
      lgt_id = lgt_active(j)
      ! first index stores the light id of the block
      lgt_sortednumlist(j, 1) = lgt_id
      ! second index stores the numerical treecode
      lgt_sortednumlist(j, 2) = treecode2int( lgt_block(lgt_id, 1:params%max_treelevel) )
    enddo

    ! sort list
    if (lgt_n > 1) then
      call quicksort(lgt_sortednumlist, 1, lgt_n)
  endif
end subroutine create_lgt_sortednumlist



recursive subroutine quicksort(a, first, last)
  implicit none
  integer(kind=tsize), intent(inout) ::  a(:,:)
  integer(kind=tsize), dimension(2) :: x, t
  integer(kind=ik) :: first, last
  integer(kind=ik) :: i, j

  x = a( (first+last) / 2 , 2)
  i = first
  j = last
  do
     do while (a(i,2) < x(2))
        i=i+1
     end do
     do while (x(2) < a(j,2))
        j=j-1
     end do
     if (i >= j) exit
     t = a(i,:);  a(i,:) = a(j,:);  a(j,:) = t
     i=i+1
     j=j-1
  end do
  if (first < i-1) call quicksort(a, first, i-1)
  if (j+1 < last)  call quicksort(a, j+1, last)
end subroutine quicksort